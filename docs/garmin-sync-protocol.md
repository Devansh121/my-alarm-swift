# Garmin watch sync protocol (v1)

The iOS app and the Connect IQ watch app (`garmin/`) keep the same alarm list.
The phone is the source of truth: it owns scheduling, ringing and every field
the watch can't edit (tone, per-day times, ramp, vibrate-first, snooze state).
The watch keeps a cached copy, edits it optimistically, and sends its edits as
operations.

Transport is the Connect IQ Mobile SDK (iOS) and `Toybox.Communications` (watch).
Messages are dictionaries of strings, integers, booleans and arrays; a missing
key means "no value" (no nulls are sent).

## Phone → watch: `snap`

Sent whenever the phone's alarm list changes, after every `sync` from the watch,
and when the watch connects.

```json
{
  "t": "snap",
  "v": 1,
  "ts": 1790000000,
  "ack": ["w1a2b-3", "w1a2b-4"],
  "alarms": [ <alarm>, ... ]
}
```

| key | meaning |
|-----|---------|
| `ts` | phone clock when the snapshot was built (epoch seconds) |
| `ack` | `oid`s of watch operations the phone has processed (applied **or** rejected); the watch drops them from its outbox |
| `alarms` | the full list, in the phone's list order |

### `<alarm>`

| key | type | meaning |
|-----|------|---------|
| `id` | string | stable alarm id |
| `h`, `m` | int | default time, 0–23 / 0–59 |
| `d` | int[] | repeat days, ISO (1 = Mon … 7 = Sun), ascending; empty = one-shot |
| `l` | string | label |
| `e` | bool | enabled |
| `sn` | bool | snooze allowed |
| `sm` | int | snooze minutes, 1–30 |
| `u` | int | last user edit (epoch seconds); 0 if never edited since sync was added |
| `nf` | int? | next scheduled fire (epoch seconds), absent when off |
| `sk` | int? | skipped occurrence (epoch seconds), absent when no skip |
| `sz` | int? | pending snooze re-ring (epoch seconds) |
| `ov` | dict? | per-day times, `{"5": [8, 30]}` = Friday 08:30; absent when none |

The watch shows `ov` but never edits it.

## Watch → phone: `sync`

Sent when the watch app starts, after every edit, and on "Sync now". It always
carries the whole outbox, so a lost message is repaired by the next one.

```json
{ "t": "sync", "v": 1, "ops": [ <op>, ... ] }
```

The phone answers every `sync` with a `snap`, so an empty `ops` works as "hello".

### `<op>`

| key | meaning |
|-----|---------|
| `oid` | unique operation id (watch-generated) |
| `op` | `put`, `del`, `en`, `skip`, `unskip` |
| `id` | alarm id (for a new alarm the watch picks a new id, `w…`) |
| `at` | when the user made the edit on the watch (epoch seconds) |
| `f` | `put` only: the fields to set (`h`, `m`, `d`, `l`, `sn`, `sm`; any subset) |
| `e` | `en` only: the new enabled value |

- `put` on an unknown id creates the alarm (phone defaults for every field not
  in `f`; `h` and `m` are required). On a known id it changes only the fields in `f`.
- `en` is the list toggle. It goes through the same path as the phone's toggle,
  so turning a snoozed alarm off also ends its snooze.
- `skip` / `unskip` are "Skip next" / "Cancel skip"; the phone works out which
  occurrence. Skipping a one-shot turns it off, as on the phone.

## Conflict rules (phone side)

Each alarm carries `u`, the time of its last user edit. Applying a watch op
sets `u` to the op's `at`, not to the phone's clock, so several queued ops for
one alarm all apply in order. Phone-side edits set `u` to the phone's clock.

For each op, in order:

1. The alarm exists and `u > at`: the phone has a newer edit. The op is rejected.
2. The alarm was deleted on the phone (tombstone) after `at`: rejected.
   A `put` made on the watch **after** the phone deleted the alarm recreates it.
3. `en`, `skip`, `unskip`, `del` on an unknown id: nothing to do.
4. A `put` with an invalid value (hour 25, empty label, day 9, …) is rejected whole. Labels are trimmed and cut to 40 characters.
5. Otherwise the op is applied.

Every processed op is acked, applied or not. The next `snap` shows the result,
which is how a rejected watch edit "snaps back" on the watch.

Tombstones are kept for 30 days.

## Watch side

- Storage keeps the last snapshot (`alarms`), the outbox (`outbox`), when the last
  snapshot arrived (`syncedAt`) and an op counter (`seq`).
- The list shown is the snapshot with the outbox replayed on top. An alarm
  with a pending op shows a "syncing" mark.
- A `snap` drops acked ops from the outbox and replaces the cached snapshot.
  Ops that are not acked stay and are resent with the next `sync`.
- The background service receives a `snap` while the app is closed
  (`Background.registerForPhoneAppMessageEvent`) and writes it to storage.
- The outbox holds at most 64 ops; past that the oldest are dropped
  (the phone's state wins for those).

## Versioning

`v` is the protocol version. A side that receives a higher `v` than it knows
ignores the message. Fields may be added within a version; unknown keys
must be ignored.
