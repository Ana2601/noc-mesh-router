# Network-on-Chip: 5-port wormhole router and 4×4 mesh

[![CI](https://github.com/Ana2601/noc-mesh-router/actions/workflows/ci.yml/badge.svg)](https://github.com/Ana2601/noc-mesh-router/actions/workflows/ci.yml)

Packet-switched on-chip interconnect: a parameterised router and a 2-D mesh generator, verified under random traffic up to saturation.

## Router microarchitecture

- 5 ports (Local, N, E, S, W), an input FIFO per port, valid/ready link-level flow control
- **XY dimension-order routing**, which is deadlock-free on a mesh
- **Wormhole switching**: an output is locked from head flit to tail flit, so packets never interleave
- **Per-output round-robin arbitration** (starvation-free)
- Single-cycle hop: a head-of-line flit can enter the next router's FIFO on the next clock

Flit = `{type[1:0], data[31:0]}`: head / body / tail / head+tail; the head flit carries the destination (x, y).

## Verification

`tb/tb_noc.sv` drives all 16 nodes at once with random-length packets (1–7 flits) to uniformly random destinations, with random back-pressure at every sink. The scoreboard checks:

- correct destination (no misrouting)
- in-order delivery per (source, destination) flow
- no interleaving inside a packet
- payload integrity of every flit
- nothing lost or duplicated, and the network drains completely (no deadlock)

The test caught a real bug during development: the round-robin pointer arithmetic overflowed 3 bits and starved some inputs. It is fixed and documented in `rtl/noc_router.sv`.

## Results (measured, 4×4 mesh, 20,000 cycles per point)

| Offered load (flits/node/cycle) | Accepted | Avg latency (cycles) | Max latency |
|---|---|---|---|
| 0.05 | 0.045 | 7.8 | 21 |
| 0.10 | 0.092 | 8.0 | 22 |
| 0.20 | 0.164 | 8.5 | 31 |
| 0.30 | 0.230 | 9.1 | 47 |
| 0.40 | 0.283 | 9.6 | 52 |
| 0.60 | 0.365 | 11.1 | 67 |
| 0.90 | 0.441 | 13.7 | 92 |

Regression: up to 22,263 packets / 89,378 flits per run, **0 errors**, at 10 %, 40 % and 90 % load with 10–50 % sink back-pressure.

## Run

```bash
make test     # 3 load / back-pressure corners
make sweep    # latency vs. load table
make lint
```

## Limitations / next steps

No virtual channels (head-of-line blocking limits saturation throughput) and no adaptive routing.

## Setup

- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (Icarus Verilog, Verilator, Yosys)

```bash
make test
make lint
```

The same commands run in CI on every push (`.github/workflows/ci.yml`).
