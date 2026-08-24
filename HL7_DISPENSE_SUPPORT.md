# HL7 Dispense — Segment/Field Support

Scope: dispense flow only (inbound order/result → transaction → outbound completion). Inventory doc separate.

## Inbound: PMS → Device

Message: `RDE^O11` (standard path via ORC+RXE), or vendor-custom `ZUI`/`ZNI` packet (no ORC/RXE).

Entry: `Hl7ServiceManager.swift:351` parse → `PillScanViewModel+HL7.swift:65 classifyInboundMessage()` route.

### MSH
| Field | Meaning | Used for |
|---|---|---|
| MSH-9 | message type | routing (RDE check) |
| MSH-10 | message control ID | stored `hl7_message_control_id`, used for image server lookup |

### ORC (order control)
| Field | Meaning | Used for |
|---|---|---|
| ORC-1 | control code (NW/XO/CA) | routes to create / edit / cancel transaction |
| ORC-2 | placer order number | stored as `rx_no` (encrypted), transaction key |
| ORC-5 | order status | mapped: IP→PARTIAL, CM→COMPLETED, HD→ON_HOLD, CA→soft-delete; drives sync queue |

### RXE (order detail)
| Field | Meaning | Used for |
|---|---|---|
| RXE-2.1 | NDC | drug lookup (local DB, API fallback), stored `drug_id` |
| RXE-2.2 | drug name | fallback drug creation, shown in History detail screen |
| RXE-3 | dispense amount (parsed via workaround, lib bug) | stored `target_count`, compared vs actual pill count in UI |

### ZPR (custom, priority) — optional segment
| Field | Meaning | Used for |
|---|---|---|
| ZPR-2 | priority (STAT/URGENT/ROUTINE/TIMED) | stored `txn_priority` — **stored only, not shown in current UI** |

### ZIN (custom, inventory pre-fill) — optional segment
| Field | Meaning | Used for |
|---|---|---|
| ZIN-2.3 | dispense type = EXPECTED_ON_HAND | pre-fills first workflow step count in transaction detail |

### ZUI (vendor alt: Vivid order packet, replaces ORC+RXE)
NDC, drug name, dispense qty, Rx number, order ID — all feed same create-transaction path as RXE.

### ZNI (vendor alt: Eyecon dispense result, replaces ORC+RXE)
NDC, drug name, dispense amount, prescription number, filler order number — same as above.

## Stored but not surfaced in UI
- `hl7_message_control_id` — lookup key only
- `transaction_order_id` (from ZUI/ZNI) — lookup key only
- `txn_priority` (ZPR-2) — stored, not displayed
- `is_from_pms` — used for sort order only

No dead parses found — everything parsed either drives logic or is a lookup key.

## Outbound: Device → PMS (dispense completion)

Message: `RDS^O13`, built in `HL7MessageBuilder.swift:56` from `PillCountTransactionEntity`.

| Segment | Key fields | Source |
|---|---|---|
| MSH | control ID, timestamp, version | app config |
| ORC | ORC-1="RE", ORC-2=rx_no, ORC-5="CM" | transaction |
| PID | PID-3 = order ID | transaction |
| RXD | RXD-2 NDC/name, RXD-4 actual qty, RXD-11 Rx number, RXD-16 user ID | transaction + drug + user |
| NTE | txn id, status, total count, note | transaction |
| OBX | image refs (pill-count + barcode images) | image files |
| ZSN (custom) | per-bottle: NDC, qty, lot, expiry, serial | bottle scan data |
| ZSV (custom) | NDC match validation result | NDC verification flag |

Trigger: transaction status → COMPLETED → `HL7TxnSyncQueue` enqueues → build → send → ACK → `is_synced=true`.

## Key files
- Parse/route: `PillScanViewModel+HL7.swift`
- Store: `TransactionStore.swift`
- Build outbound: `HL7MessageBuilder.swift`
- Send/ACK: `Hl7ServiceManager.swift`
- Display: `HistoryTransactionDetailView.swift`, `RxDetailSheetContent.swift`
