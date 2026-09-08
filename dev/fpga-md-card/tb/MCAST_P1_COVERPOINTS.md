# mcast_eng P1 TB coverpoints

Source: `docs/udp-mcast-tx-p1-impl.md` §4.  
TB: `/workspace/fpga-md-card/tb/test_mcast_eng.py`  
RTL: `/workspace/fpga-md-card/rtl/mcast_eng.sv`

## DUT port status

**P1 ports ARE present** (码农 landed RTL). Verified green via `make sim-mcast`.

| Port | Dir | Default / note |
|---|---|---|
| `i_cfg_ttl_default` | in  | 8'd1; 0 treated as 1 |
| `i_cfg_map_en`      | in  | 1 |
| `o_err_addr_sticky` | out | sticky, rst-clear |
| `o_err_mac_mismatch`| out | sticky, rst-clear |

## Tests

| Test | Expectation |
|---|---|
| `test_tx_roundtrip` (updated) | TTL==1, DA=`MAPPED_DA` `01:00:5e:01:01:01` |
| `test_ip_checksum` (updated) | frame csum validates with TTL=1 |
| `test_drop_filt_*` / `test_token_bucket_drop_rate` | under defaults ttl_default=1, map_en=1 |
| `test_map_da` | map_en=1 ignores wrong CSR MAC → RFC1112 DA |
| `test_ttl_default_1` | TTL byte==1; csum golden; cfg=0 → TTL 1 |
| `test_bad_sa_group` | src∈224/4 → no TX, `o_err_addr_sticky`, tready=1 |
| `test_bad_da_unicast` | dst unicast → no TX, sticky, tready=1 |
| `test_map_en0_mismatch` | map_en=0 mac≠map → no TX, `o_err_mac_mismatch` |
| `test_map_en0_match` | map_en=0 mac==map → TX ok |

RFC1112: `mapped_mac = {24'h01005E, 1'b0, dst_ip[22:0]}`  
Example: `239.1.1.1` (`0xEF010101`) → `01:00:5e:01:01:01`.
