# Squeek (SQK)

Squeek is an immutable ERC-20. Its constructor mints the full supply once to its
immediate deployer. The only production contract is `src/Squeek.sol:Squeek`.

| Property | Value |
| --- | --- |
| Token name | `Squeek` |
| Symbol | `SQK` |
| Decimals | `18` |
| Supply in SQK | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Solidity identifier | `Squeek` |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial supply recipient | Constructor `msg.sender` |
| Administrative roles | None |

## Behavior and assumptions

The brief specifies a fixed supply token; this project uses ordinary ERC-20
transfer and allowance behavior from OpenZeppelin Contracts v5.1.0. Name and
symbol are fixed in the constructor. `INITIAL_SUPPLY` is the named constant for
the one billion tokens expressed in base units. The inherited decimal count is
18. Transfers deliver their exact amount, and total supply never changes after
construction. There are no taxes, burns, rebases, transfer restrictions, minting
entry points, owner, pause mechanism, blacklist, upgrade mechanism, or initializer.

The exposed interface is `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`,
`allowance`, `transfer`, `approve`, `transferFrom`, and `INITIAL_SUPPLY`. Successful
state-changing ERC-20 calls return `true`; invalid operations revert with the
OpenZeppelin ERC-6093 custom errors. The constructor emits a `Transfer` from the
zero address for the whole supply. Transfers (including zero amounts) emit
`Transfer`, and approvals emit `Approval`.

Zero-value transfers to nonzero addresses are valid. Transfers to the zero
address and approvals to the zero spender revert. Self-transfers preserve
balances. A finite allowance is consumed by `transferFrom`; a maximum `uint256`
allowance is treated as unlimited and is not reduced. In this OpenZeppelin
version, consuming an allowance does not emit another `Approval`; clients should
query `allowance` for the current value. Failed transfers revert all balance and
allowance changes. `transferFrom` requires allowance even when the spender is
also the source account, except that an amount of zero needs no allowance.

## Build and test

Use Foundry with Solidity **0.8.26** installed. All source dependencies and their
licenses are vendored as regular files under `lib/`; the build needs no dependency
installation, RPC, credentials, environment configuration, FFI, or filesystem
cheatcodes. See [DEPENDENCIES.md](DEPENDENCIES.md) for versions and provenance.

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x183dba788249b083da55c2f6085e20c527864c8306a5dce9f11a62e6ea68a5df forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization at 200
runs, and `bytecode_hash = "none"`. Fuzz tests run 1,024 cases per test; stateful
invariants run 256 sequences of 64 operations. Tests construct independent local
fixtures and do not read or mutate environment variables. The fuzz seed above
is the assignment's verification seed, supplied to the test runner only.

- `test/Squeek.t.sol` covers metadata, constructor minting and event emission,
  direct and CREATE2 factory deployment, exact launch-like distribution and
  return transfers, standard transfers, allowances, revocation, boundary values,
  failure rollback, and rejection of minting and administrative calls. Fuzz tests
  check conservation, arbitrary recipients, allowance spending and overspending.
- `test/Squeek.invariant.t.sol` runs transfers, approvals, delegated transfers,
  and rejected operations among four actors against an independent accounting
  model. It checks every tracked balance and allowance and the constant supply.

The local factory test demonstrates token movement only. The supplied protected
checks use the launch infrastructure and a real Uniswap v4 PoolManager; those
checks require the verifier's separate infrastructure and resolved launch data.
The local suite does not claim to execute that integration.

## Deployment parameters and responsibilities

The intended chain is Ethereum (chain ID 1). Deploy the creation bytecode built
for `src/Squeek.sol:Squeek`, with no constructor arguments and no ETH. It contains
no external library links or constructor calls to other contracts. Do not deploy
through a proxy. No deployment script or post-deployment initializer is needed.

The authorized launch system deploys through its factory. The factory therefore
receives all `10^27` base units; the transaction origin and requester receive none
from the token constructor. The factory handles all launch distribution. The
token does not hard-code a factory, pool manager, distributor, or recipient, and
does not require any exemption or setup to transfer to them. A direct deployment
would instead credit the direct deploying wallet or contract.

The assignment's launch economics are external to the token: 10% of the supply
goes to the launch distributor, 80% seeds the pool, and the remaining 10% goes to
`0x433c89e346976a3686cc237fcfe14d4eb84c831d`. The pair is IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, with pool fee `12500` (1.25%), tick
spacing `60`, and initial market capitalization `3900000000000000000000` in
IMD base units. These are supplied launch parameters, not independently verified
chain state or token contract settings. The launch system derives the opening
price. Its separate manifest step supplies `launch.json`; this project does not.

Before release, the launch operator is responsible for independent adversarial
review, manifest accuracy, factory deployment, distribution and liquidity setup,
and explorer source verification using the pinned compiler settings. Confirm
metadata, total supply and the constructor mint recipient from deployment
receipts. This assignment performs no broadcast or signing.

## After launch

There are no owner-settable settings, privileged operators, keepers, or required
maintenance transactions. No one can mint more supply, freeze holders, recover
lost balances, or upgrade the contract. Holders are responsible for custody,
checking recipients, and managing spender approvals. Restrict approvals to the
amount needed; maximum approval allows the spender to use future balances too.
When replacing an existing allowance, first revoke it and wait for confirmation
to reduce the standard ERC-20 allowance replacement race.

The token has no recovery function. Tokens sent to this token contract or another
contract without a withdrawal path can become inaccessible. Ordinary ETH sends
revert; ETH forced into the address cannot be withdrawn. Such transfers do not
change the fixed total supply.

## Security review scope

The implementation adds only the constructor mint and a supply constant to the
vendored ERC-20. It makes no external calls, uses no price feeds or randomness,
and exposes no privilege or upgrade path. The reviewed failure cases include
unauthorized spending, zero addresses, balance and allowance underflow,
self-transfers, and transaction rollback after allowance spending. Standard
ERC-20 transfers do not invoke recipient callbacks.

Foundry build, unit/fuzz tests, stateful invariants and formatting checks are the
local validation tools. Slither, Mythril, deployment verification and an
independent security audit are not performed by this project. Passing local
tests is not a substitute for the launch's independent review.
