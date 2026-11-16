enum UsageFixtures {
    static let teamActive = """
    {
      "five_hour":  { "utilization": 1.0, "resets_at": "2026-11-14T22:10:00.502237+00:00" },
      "seven_day":  { "utilization": 0.0, "resets_at": "2026-11-21T08:00:00.502262+00:00" },
      "limits": [
        { "kind": "session",       "group": "session", "percent": 1, "severity": "normal",
          "resets_at": "2026-11-14T22:10:00.502237+00:00", "scope": null, "is_active": true },
        { "kind": "weekly_all",    "group": "weekly",  "percent": 0, "severity": "normal",
          "resets_at": "2026-11-21T08:00:00.502262+00:00", "scope": null, "is_active": false },
        { "kind": "weekly_scoped", "group": "weekly",  "percent": 0, "severity": "normal",
          "resets_at": "2026-11-21T08:00:00.502483+00:00",
          "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
          "is_active": false }
      ]
    }
    """

    static let idleNullFiveHour = """
    {
      "five_hour": null,
      "seven_day": { "utilization": 4.0, "resets_at": "2026-11-21T08:00:00.502262+00:00" },
      "limits": [
        { "kind": "weekly_all", "group": "weekly", "percent": 4, "severity": "normal",
          "resets_at": "2026-11-21T08:00:00.502262+00:00", "scope": null, "is_active": false }
      ]
    }
    """

    static let idleZeroSession = """
    {
      "five_hour": { "utilization": 0.0, "resets_at": null },
      "seven_day": { "utilization": 0.0, "resets_at": "2026-11-21T08:00:00.502262+00:00" },
      "limits": [
        { "kind": "session", "group": "session", "percent": 0, "severity": "normal",
          "resets_at": null, "scope": null, "is_active": false },
        { "kind": "weekly_all", "group": "weekly", "percent": 0, "severity": "normal",
          "resets_at": "2026-11-21T08:00:00.502262+00:00", "scope": null, "is_active": false }
      ]
    }
    """

    static let legacyOnly = """
    {
      "five_hour": { "utilization": 37.5, "resets_at": "2026-11-14T22:10:00.502237+00:00" },
      "seven_day": { "utilization": 12, "resets_at": "2026-11-21T08:00:00.502262+00:00" }
    }
    """

    static let noise = """
    {
      "five_hour": { "utilization": 1.0, "resets_at": "2026-11-14T22:10:00.502237+00:00" },
      "seven_day": { "utilization": 0.0, "resets_at": "2026-11-21T08:00:00.502262+00:00" },
      "tangelo": null, "iguana_necktie": {"x": [null]}, "k03": null, "k04": null,
      "k05": null, "k06": {"a": null}, "k07": [], "k08": null, "k09": 3, "k10": "s",
      "k11": null, "k12": null, "k13": null, "k14": {"b": {"c": null}}, "k15": null,
      "k16": null, "k17": null, "k18": [null, null], "k19": null, "k20": null,
      "k21": null, "k22": null, "k23": null, "k24": null, "k25": null,
      "limits": [
        { "kind": "session", "group": "session", "percent": 1, "severity": "normal",
          "resets_at": "2026-11-14T22:10:00.502237+00:00", "scope": null, "is_active": true,
          "extra": null },
        { "kind": "weekly_all", "group": "weekly", "percent": 0, "severity": "elevated",
          "resets_at": "2026-11-21T08:00:00.502262+00:00", "scope": null, "is_active": false },
        { "kind": "mystery", "percent": "12" },
        { "kind": "weekly_scoped", "group": "weekly", "percent": 12.5, "severity": "normal",
          "resets_at": null,
          "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
          "is_active": false }
      ]
    }
    """

    static let emptyLimits = #"{"five_hour": null, "seven_day": null, "limits": []}"#
}
