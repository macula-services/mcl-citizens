# mcl-citizens

**The citizens directory for the Macula mesh: who exists, federated across instances by mesh facts**

Built on macula 12 and `mcl_om`.

## What it does

A public phone book of who is on the mesh right now. It serves three
procedures, all open, and answers `/health` on 8486.

| Procedure | Payload | Reply |
|-----------|---------|-------|
| `mcl-citizens/register_presence` | optional `citizen_kind`, `display_name`, `offers` (list), `ttl_ms` (default and maximum 20 minutes), and optionally `citizen_did` | `#{ok => 1, expires_at => Ms}` or `#{ok => 0, error => Text}` |
| `mcl-citizens/list_citizens` | none | `#{ok => 1, citizens => [Citizen]}` |
| `mcl-citizens/get_citizen` | `citizen_did`, 64 hex text | `#{ok => 1, citizen => Citizen}` or `#{ok => 0, error => <<"not_found">>}` |

A `Citizen` is `citizen_did` (lowercase hex text), `citizen_kind`,
`display_name`, `offers`, `registered_at` and `expires_at` (milliseconds),
absent fields omitted. Every string goes out as `{text, Bin}`, so callers
outside the BEAM get strings and not hex.

**A citizen registers itself and nobody else.** macula 12 signs every CALL with
the caller's identity key and verifies it here before the handler runs, so the
registration is the verified caller's own and no proof travels in the payload.
A `citizen_did` sent anyway must be the caller's, or the call is refused with
`citizen_did_is_not_the_caller`.

**Entries expire.** An entry lives for its `ttl_ms` from `registered_at`, at
most twenty minutes; clients re-register about every five. The latest
registration wins, by `registered_at`.

**The directory is soft state, empty after a restart for up to one republish
interval.** It is held in memory, not on disk: every entry expires within
twenty minutes anyway, and client re-registrations and the other instances'
facts refill it.

**Instances federate.** Each registration is published as the fact
`<realm>/mcl-citizens/citizens/directory/citizen_presence_registered_v1`. An
instance admits a fact only from a publisher whose signature macula verified
and whose node id is in `MCL_CITIZENS_PRESENCE_PUBLISHERS`, and computes the
expiry itself from the fact's `registered_at` and `ttl_ms`. A registration
stamped more than a minute ahead of the receiving clock is refused.

`/health` is `down` without the directory and `degraded` while the federation
subscription is not held, which includes a dark mesh.

## Running it

    rebar3 compile
    rebar3 eunit
    rebar3 lint
    rebar3 dialyzer

    scripts/health.sh                      # against a running node

Building the image needs a Rust toolchain, because macula ships a QUIC NIF and
the alpine build compiles it from source rather than fetching one linked against
a different libc.

    podman build -t mcl-citizens -f Containerfile .

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `MCL_REALM` | required | 64-hex realm tag, the `sha256` of the realm's name. No default: a service that guesses its realm announces itself where nobody can attribute it. |
| `MCL_REALM_KEY` | required | The realm's public signing key, hex encoded: the **trust anchor**, not an identifier. Every org-namespaced advertisement is verified against it, so without it nothing resolves, the boot claim never reaches the realm, and the service stays green while unreachable. Public material, not a secret. |
| `MACULA_STATION_SEEDS` | required | Station hosts to dial, `host[:port]`, comma-separated. No default: naming a realm costs nothing, dialling a production station from every dev clone does. |
| `MACULA_STATION_NODE_IDS` | required | The matching 64-hex station node ids, comma-separated, index-paired with the seeds. The dial is pinned (D5): mcl_om refuses to boot a pool with an unpinned seed. |
| `MCL_REALM_NAME` | required | The realm's name, as the fact topic carries it. At start, `sha256` of it must equal `MCL_REALM` or the node refuses to start. |
| `MCL_CITIZENS_PRESENCE_PUBLISHERS` | required | Node ids of the mcl-citizens instances to federate with, 64 hex each, comma separated. This instance's own is optional. Missing or malformed stops the node. |
| `MCL_HEALTH_PORT` | `8486` | Health endpoint, assigned in macula-fleet `PORTS.md`. Host networking makes a collision a silent bind failure, so take a new one from there rather than picking one. |
| `MCL_NODE_NAME` | `mcl_citizens` | Erlang node name. |
| `MCL_NODE_HOST` | `127.0.0.1` | Erlang node host. |
| `MCL_COOKIE` | `mcl_citizens` | Erlang cookie. |

`deploy/docker-compose.yml` runs it, and carries what the service knows about
itself. If you deploy through something else, let that carry **placement**: which
host, which station, which realm, which secret store. Keeping the two apart is
what stops a config table in a README and the real environment drifting.

## Deployment

The image has two channels. A push to `main` publishes
`ghcr.io/macula-services/mcl-citizens:latest`, the deploy channel: a host that follows
`:latest` deploys every merge. A `v*` tag publishes its own version and nothing
else, the rollback archive: pin a host to one to roll back. A push that changes
only documentation builds no image (`scripts/is_image_push.sh`).

The service's org, the `<org>` in every procedure it offers (`<org>/<name>`), is
this repository's name, fixed in `config/sys.config.src`. The realm's grant names
it; without an org mcl_om advertises nothing.

Two things CI cannot do for you, both of which have bitten:

1. The registry package may be created **private**, and the pull then fails on
   the host with a bare `unauthorized` that names nothing. Check it after the
   first build. On ghcr the `org.opencontainers.image.source` label in the
   Containerfile is what links the package to the repository.
2. The host needs `MCL_REALM`, `MCL_REALM_NAME`, the instance list and the
   pinned station pair supplied from somewhere they are not committed.

## The service contract

Six callbacks in `mcl_citizens_service`, all required, all resolved **by name** by
`mcl_om` at startup on a live node. The `-behaviour(mcl_om_service)`
attribute turns a missing one into a compile error rather than an `undef` where
nobody is watching, and the eunit suite guards the attribute itself.

### Adding a store later

This service has no `reckon-db` store, which is the right answer for most. The
reckon-db applications run either way; what a store adds is a data directory, an
open handle, and something written.

The cheapest way to get one is to scaffold again with `store=1`, which generates
the callbacks, the config and the guards together.

⚠ **By hand it is three things and not one, and the missing third crash-loops the
node.** Export `store_id/0` and `data_dir/0`; add the `evoq` adapter block to
`config/sys.config.src`, without which boot raises
`{not_configured, event_store_adapter}` before any service code runs; and mount a
volume in the compose file. A sibling service put two of three fleet nodes into a
boot loop by doing the first and not the second.

## Licence

Apache-2.0.
