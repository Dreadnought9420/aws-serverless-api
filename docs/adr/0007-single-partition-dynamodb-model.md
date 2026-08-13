# ADR-0007: Single-partition DynamoDB model

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

The demo API stores short messages and lists them newest-first. DynamoDB can
only sort within a partition, so "list everything in time order" and "spread load
across partitions" pull in opposite directions.

This is the classic DynamoDB tension, and the textbook answer — never use a
single hot partition — is correct at scale and wrong here, so it needs writing
down rather than quietly ignoring.

## Decision

Use one item collection:

```
pk = "ITEM"
sk = "<zero-padded epoch seconds>~<uuid4>"
```

The sort key is what the API exposes as the item `id`, so reads and deletes are a
single `GetItem` / `DeleteItem` with no secondary index. Listing is a `Query` on
`pk` with `ScanIndexForward = false`.

`~` separates the two halves because it requires no escaping in a URL path;
`#`, the conventional separator, would be parsed as a fragment by a browser.

## Options Considered

### Option A: Single partition, time-ordered sort key (chosen)

| Dimension | Assessment |
| --- | --- |
| Complexity | Lowest — no index, no scatter-gather |
| Cost | Lowest — one table, no GSI replication |
| Scalability | Caps at ~3,000 RCU / 1,000 WCU for the partition |
| Read pattern fit | Exact — newest-first listing is one Query |

**Pros:** listing is one request; get and delete are O(1); no index to keep
consistent; no eventual-consistency surprises.
**Cons:** a single logical partition is a hard throughput ceiling and would be a
serious design flaw in a real multi-tenant system.

### Option B: Partition per time bucket (for example per day) with a GSI

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium — the reader must fan out across buckets |
| Cost | Higher — GSI storage and write amplification |
| Scalability | Good |
| Read pattern fit | Good, with more client-side work |

**Pros:** spreads writes; the standard answer for a real feed.
**Cons:** "the last 25 items" becomes a query per bucket plus a merge, for a
dataset that will hold tens of items.

### Option C: `id` as the partition key plus a GSI for time ordering

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium |
| Cost | Higher — GSI storage and writes |
| Scalability | Good for writes; the GSI partition is still hot for reads |
| Read pattern fit | Good |

**Pros:** perfectly distributed writes; `GetItem` by id is natural.
**Cons:** the GSI needed for time ordering has exactly the same hot-partition
property as option A, so it moves the problem rather than solving it, at the
cost of an index.

## Trade-off Analysis

Option A's ceiling is roughly 3,000 reads and 1,000 writes per second on one
partition. This API has a reserved concurrency of 10 and sits behind CloudFront.
The Lambda concurrency limit binds thousands of times before the partition does,
so the theoretical flaw cannot be reached in practice.

Option C is the interesting near-miss: it looks like it fixes the hot partition,
but the GSI it requires reintroduces one on the read path while adding storage
and write amplification.

The decision is therefore explicitly scale-bounded. If this table ever backed
something real and multi-tenant, `pk` would become the tenant or user id and this
record would be superseded.

## Consequences

- Reads and deletes are single-request and strongly consistent by default.
- No GSI: no index storage, no write amplification, no eventual-consistency
  window between writing an item and it appearing in a list.
- The write ceiling is a single partition. This model does not survive contact
  with real multi-tenant traffic.
- The item `id` is opaque and contains a timestamp, so it is not a secret and
  must not be treated as one.
- TTL (`expires_at`) prunes items automatically, which keeps the partition small
  as well as the bill.

## Action Items

1. [x] Validate the id format in the handler before it reaches DynamoDB
2. [x] Enable TTL so the partition self-prunes
3. [ ] Supersede this record if the table ever holds per-user data
