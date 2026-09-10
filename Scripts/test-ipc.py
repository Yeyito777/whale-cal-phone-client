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
                if response.get("reqId") == req or (kind == "bootstrap" and response["type"] == "bootstrap"):
                    assert response["type"] != "error", response
                    return response
        assert request("probe")["type"] == "pong"
        calendar = request("create_calendar", name="Phone IPC test")["calendar"]
        group = request("create_group", name="Phone test group")["group"]
        assert request("update_group", id=group["id"], name="Renamed")["group"]["name"] == "Renamed"
        assert any(g["id"] == group["id"] for g in request("list_groups")["groups"])
        grouped = request("update_calendar", id=calendar["id"], patch={"groupId": group["id"]})["calendar"]
        assert grouped["groupId"] == group["id"] and grouped["visible"]
        assert request("update_calendar", id=calendar["id"], patch={"groupId": None})["calendar"].get("groupId") is None
        request("update_calendar", id=calendar["id"], patch={"groupId": group["id"]})
        event = request("create_event", event={"kind": "event", "title": "Repeated study", "calendarId": calendar["id"],
            "startDate": "2026-09-07", "endDate": "2026-09-07", "startTime": "09:00", "endTime": "10:00",
            "notes": "Paragraph one.\n\nUnicode 🐋", "location": "Desk", "recurrence": {"frequency": "weekly", "interval": 1, "count": 3}})["event"]
        request("complete_event", id=event["id"], completed=True, occurrenceDate="2026-09-14")
        occurrences = request("list_events", **{"from": "2026-09-01", "to": "2026-09-30"})["occurrences"]
        assert len(occurrences) == 3
        assert occurrences[1]["event"]["completedDates"] == ["2026-09-14"]
        request("delete_group", id=group["id"])
        preserved = next(c for c in request("list_calendars")["calendars"] if c["id"] == calendar["id"])
        assert preserved.get("groupId") is None and preserved["visible"]
        assert len(request("list_events", **{"from": "2026-09-01", "to": "2026-09-30"})["occurrences"]) == 3
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
        # Validate the phone's local expansion against the daemon's exact dates/IDs.
        parity_calendar = request("create_calendar", name="Recurrence parity")["calendar"]
        for start, end, frequency, interval in [
            ("2024-01-31", "2024-01-31", "monthly", 1),
            ("2024-02-29", "2024-02-29", "yearly", 1),
            ("2024-03-09", "2024-03-11", "weekly", 2),
            ("2024-10-31", "2024-11-01", "daily", 3),
        ]:
            request("create_event", event={"calendarId": parity_calendar["id"], "title": frequency, "startDate": start,
                "endDate": end, "startTime": "09:00", "endTime": "10:00", "recurrence": {"frequency": frequency, "interval": interval, "count": 30}})
        request("update_calendar", id=parity_calendar["id"], patch={"visible": False})
        database = request("bootstrap")["database"]
        assert any(c["id"] == parity_calendar["id"] and not c["visible"] for c in database["calendars"])
        cases = [("2024-01-01", "2028-12-31"), ("2024-03-10", "2024-04-30")]
        for start, end in cases:
            expected = request("list_events", **{"from": start, "to": end, "includeHidden": True})["occurrences"]
            binary = pathlib.Path(__file__).resolve().parents[1] / ".build/recurrence-parity"
            actual = json.loads(subprocess.check_output([str(binary)], input=json.dumps({"events": database["events"], "from": start, "through": end}).encode()))
            key = lambda x: (x["id"], x["startDate"], x["endDate"], x["occurrenceIndex"])
            assert sorted(map(key, expected)) == sorted(map(key, actual)), "phone/daemon recurrence mismatch"
        stream.close(); sock.close()
        print("PASS: isolated daemon CRUD, groups, completion, bootstrap including hidden calendars, and Swift/daemon recurrence parity")
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
