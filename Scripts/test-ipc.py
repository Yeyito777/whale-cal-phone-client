#!/usr/bin/env python3
"""Verify phone command shapes against an isolated real daemon. Never touches live data."""
import json, os, pathlib, socket, subprocess, tempfile, time, uuid

repo = pathlib.Path(os.environ.get("WHALE_CAL_REPO", pathlib.Path(__file__).resolve().parents[2] / "whale-cal"))
with tempfile.TemporaryDirectory(prefix="wcal-", dir="/tmp") as temp:
    process = subprocess.Popen(["bun", "run", "daemon/src/main.ts"], cwd=repo,
                               env={**os.environ, "CAL_CONFIG_DIR": temp}, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        path = pathlib.Path(temp) / "runtime/cald.sock"
        for _ in range(100):
            if path.exists(): break
            if process.poll() is not None: raise RuntimeError(process.stderr.read().decode())
            time.sleep(.05)
        sock = socket.socket(socket.AF_UNIX); sock.settimeout(5); sock.connect(str(path))
        stream = sock.makefile("rwb", buffering=0)
        def request(kind, **kwargs):
            req = str(uuid.uuid4())
            stream.write((json.dumps({"type": kind, "reqId": req, **kwargs}) + "\n").encode())
            while True:
                response = json.loads(stream.readline())
                if response.get("reqId") == req:
                    assert response["type"] != "error", response
                    return response
        assert request("probe")["type"] == "pong"
        calendar = request("create_calendar", name="Phone IPC test")["calendar"]
        event = request("create_event", event={"kind": "event", "title": "Repeated study", "calendarId": calendar["id"],
            "startDate": "2026-09-07", "endDate": "2026-09-07", "startTime": "09:00", "endTime": "10:00",
            "notes": "Paragraph one.\n\nUnicode 🐋", "location": "Desk", "recurrence": {"frequency": "weekly", "interval": 1, "count": 3}})["event"]
        request("complete_event", id=event["id"], completed=True, occurrenceDate="2026-09-14")
        occurrences = request("list_events", **{"from": "2026-09-01", "to": "2026-09-30"})["occurrences"]
        assert len(occurrences) == 3
        assert occurrences[1]["event"]["completedDates"] == ["2026-09-14"]
        request("complete_event", id=event["id"], completed=False, occurrenceDate="2026-09-14")
        converted = request("update_event", id=event["id"], patch={"kind": "deadline", "endDate": "2026-09-07", "endTime": None})["event"]
        assert converted["kind"] == "deadline" and converted.get("endTime") is None
        all_day = request("update_event", id=event["id"], patch={"startTime": None, "endTime": None, "recurrence": None})["event"]
        assert all_day.get("startTime") is None and all_day.get("recurrence") is None
        request("update_calendar", id=calendar["id"], patch={"visible": False})
        assert not request("list_events", **{"from": "2026-09-01", "to": "2026-09-30"})["occurrences"]
        request("update_calendar", id=calendar["id"], patch={"visible": True, "name": "Updated", "color": "#7aa2f7"})
        request("delete_event", id=event["id"])
        request("delete_calendar", id=calendar["id"])
        stream.close(); sock.close()
        print("PASS: isolated daemon CRUD, recurrence, occurrence completion/reopen, deadline conversion, nullable fields, visibility and calendar management")
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
