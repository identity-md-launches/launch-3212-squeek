# Squeek test properties

The suite tests the deployed `Squeek` contract through its public interface. It does
not derive an instrumented token, edit token storage, mint test balances, or use a
fork. The expected supply is independently fixed at `1_000_000_000 * 1e18`.
Existing constructor, metadata, event, launch-transfer and access-control tests in
`Squeek.t.sol` are retained.

## Discovery and coverage

The five discovery passes from the supplied Pashov fizz reference were applied
locally. Trail of Bits' property review informed the use of bounded inputs,
explicit edge cases, inverse operations, and retry-after-failure tests.

| Pass | Property and source basis | Coverage |
| --- | --- | --- |
| Conservation | The entire `10^27` supply is minted once (`src/Squeek.sol:10-15`); successful transfers move that supply without creating or losing units (`ERC20.sol:183-211`). | Every actor balance equals an independent ghost balance; the sum equals the specified supply. Self-transfers, one-unit transfers, full balances and maximum invalid amounts are exercised. |
| Round trips | Token transfers have no fee, conversion or rounding step (`ERC20.sol:183-211`). Sending an amount and returning it must restore both balances exactly. | Repeated nonzero round trips, including intermediate balance assertions; split delegated transfers compared with a single transfer of the same aggregate amount. No rounding tolerance. |
| State transitions | Approval replaces only the selected owner/spender entry (`ERC20.sol:280-291`). Finite spending consumes allowance; only `uint256.max` is unlimited (`ERC20.sol:301-310`). Reverts must undo all changes. | All 16 actor allowance pairs are checked after each handler call. Large finite approvals, revocation, unlimited-to-finite replacement, allowance exhaustion, invalid recipients and insufficient balances are covered. Retrying after supplying the missing balance must succeed without approving again. |
| Adversarial behavior | Spending requires authorization from the balance owner (`ERC20.sol:149-154`); no owner or minting entry point is added by `Squeek`. | Existing privileged-selector probes remain. A real intermediary contract cannot spend based on its caller's transaction origin. Self-transfers cannot bypass balance checks. Every holder can transfer its complete balance after a random sequence. |
| Token properties | Fixed metadata and supply (`src/Squeek.sol:10-15`), nonzero-address guards (`ERC20.sol:166-174,280-286`), and ordinary ERC-20 balance/allowance semantics. | Metadata invariance, zero transfers, zero-address rejection, approval isolation and idempotence, finite/infinite allowance boundaries, event checks, and transfers to a contract whose fallback rejects calls. |

`ERC20.sol` above means the vendored
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. The properties are
based on the assignment, exact accounting identities, and this implementation's
public ERC-20 behavior. The suite does not assert speculative vault, AMM, fee,
governance, or privileged recovery behavior.

## Stateful model

`SqueekHandler` tracks four actors. All token movements during a sequence stay
within this set, which makes summing balances exhaustive. Ghost balances start
from the specified allocation and change only on successful transfers; expected
allowances change only on approvals and successful finite spends. Neither model
uses the token's reported state to calculate expected results.

Ten selected handler actions mix transfers, full-balance transfers, approvals,
revocations, delegated spends, round trips, overdrafts, allowance overspending,
approved-but-unfunded spending, and zero-address rejection. Every rejection checks
the exact custom error. Expected reverts are handled explicitly; unexpected
handler reverts fail with the repository's existing invariant configuration.
Funded actors are selected for full-balance transfers and nonzero round trips so
these operations cannot silently become zero-value no-ops.

After each sequence, `afterInvariant` consolidates all four holders' balances at
a fresh recipient. It checks that the whole supply remains transferable and that
direct transfers leave every modeled allowance unchanged.

Inline settings specify 1,024 runs per fuzz property and 256 invariant sequences
of depth 128. The invariant runner therefore executes 32,768 handler calls, in
addition to the end-of-sequence liveness checks.

## Local verification and limits

Build and test without accessing the network or writing artifacts outside the
scratch directory:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x183dba788249b083da55c2f6085e20c527864c8306a5dce9f11a62e6ea68a5df forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

No new dependencies are required. Nothing under `test/scratch/` is needed to build
or run the delivered tests.

The supplied protected checks were read for the launch requirements. Their real
PoolManager, launch infrastructure and resolved manifest inputs are not present
in this repository. The local factory test demonstrates exact token movement;
it does not claim to run the protected pool initialization, liquidity or swap
integration. No contract defect was reproduced in the local suite.
