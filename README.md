# Debt Ledger

A manual debt tracker for the Omarchy shell with a minimal, terminal-style
panel. Record debts, track monthly payments and due dates, and see an
estimated payoff time.

## Features

- Add, edit, and remove debt entries.
- Track the debt name, due day, balance, monthly payment, one-time extra
  payment, and remaining promotional months.
- Mark entries paid. Their monthly payment is added to the available
  snowball amount.
- Allocate the snowball to one unpaid entry at a time. Its displayed payment
  and payoff estimate include the allocated amount.
- Tab and Shift+Tab between entry fields.
- Store data locally; no account, network access, or external service is used.

## Requirements

- Omarchy Quattro with Quickshell.

## Install

```bash
omarchy plugin add https://github.com/Tsukun3x/omarchy-debt-ledger.git --enable
```

The widget appears as `$$` in the bar. Click it to open the ledger.

## Uninstall

```bash
omarchy plugin remove bruce.debt-ledger
```

Uninstalling the plugin does not remove its local ledger file. Remove or back
up `debt-ledger.json` separately if you no longer need the data.

## Estimates and snowball behavior

Payoff estimates assume 0% interest, a fixed monthly payment, and one payment
per month. The optional one-time extra is counted with the next payment.
Promotional months are displayed for reference only; the estimate does not
model interest or promotional-rate changes.

The available snowball is the sum of the manually entered monthly payments
for entries marked paid. Choose one unpaid entry's **SNOW** radio control to
add the entire amount to its displayed monthly payment. The allocation is
exclusive and saved locally. Marking the target paid or deleting it clears
the allocation.

This is a tracking tool, not financial advice. Estimates are approximate and
do not account for interest, fees, payment timing, or lender-specific terms.

## Local data

Entries are saved to:

```text
${XDG_STATE_HOME:-~/.local/state}/omarchy/debt-ledger.json
```

This file is outside the plugin repository and is not included when the
plugin is published. Back it up separately if needed.

## License

MIT. See [LICENSE](LICENSE).
