# ROBOTchattyV2 🤖

A MetaTrader 5 Expert Advisor (EA) written in MQL5. It trades EURUSD on the M5 chart with a trend-and-pullback strategy, sizes its take profit from recent candle size, and shows a live dashboard on the chart. It is built for **small accounts (about $15 to $20)** and trades the smallest lot size.

> **Status:** experimental. Under testing on demo accounts and in the MT5 Strategy Tester. No profit is promised or guaranteed.

---

## Features

- **Trend + pullback entries:** buys when the fast EMA is above the slow EMA and RSI is below a limit; sells when the fast EMA is below the slow EMA and RSI is above a limit. It checks once per new M5 candle, using the last closed candle.
- **Candle-size take profit:** take profit is the typical (median) high-to-low size of the last 10 candles, so targets adapt to current volatility. It is never less than 3× the current spread.
- **Wide stop loss:** stop loss is the take profit distance multiplied by a ratio (default 2.5×).
- **Breakeven:** moves the stop to breakeven once price covers a set fraction of the way to take profit.
- **Small-account protection:**
  - skips a trade if the stop loss risk is above a percentage of the balance,
  - skips a trade if free margin is too low,
  - skips trading when the spread is too high,
  - stops opening trades for the day after a daily loss limit is reached,
  - one trade open at a time by default.
- **On-chart dashboard:** balance, equity, floating profit, today's net, profit and loss, wins and losses, all-time net for this EA, open trades, spread, and a status line that says why it isn't trading.
- **Experts log messages:** prints each trade's candle size, take profit and stop loss in pips, and the reason when a trade is skipped.

## Requirements

- MetaTrader 5 (desktop)
- A broker or demo account with EURUSD
- Recommended: chart **EURUSD, M5**

## Installation

1. Download `ROBOTchattyV2.mq5` from this repository.
2. In MT5 press **F4** to open MetaEditor.
3. Create a new Expert Advisor named `ROBOTchattyV2`, select all the template code, and paste the contents of `ROBOTchattyV2.mq5`. Alternatively, copy the file into `MQL5/Experts/` (in MT5: File → Open Data Folder).
4. Press **F7** to compile. The Errors tab should show 0 errors.
5. In MT5 open the Navigator (**Ctrl+N**), refresh Expert Advisors, and drag **ROBOTchattyV2** onto an EURUSD M5 chart.
6. In the Common tab tick **Allow Algo Trading**, and make sure the **Algo Trading** button at the top is green.

> Do not start the EA with F5 in MetaEditor. That runs it in debug mode, and it stops when the debug session ends.

## Backtesting

1. Open the Strategy Tester (**Ctrl+R**).
2. Choose Expert `ROBOTchattyV2`, symbol `EURUSD`, timeframe `M5`.
3. Modelling: **Every tick**. Delays: **Random delay** for more realistic fills.
4. Deposit: **15 to 20 USD**. Use a short, recent date range to keep tests quick.
5. Tick **Visual mode** to see the dashboard, then press **Start**.

## Inputs

| Input | Default | Description |
|---|---|---|
| `InpLots` | 0.01 | Lot size |
| `InpMagic` | 1001004 | Magic number that identifies this EA's trades |
| `InpSlippage` | 20 | Max slippage in points |
| `InpMaxPositions` | 1 | Max trades open at once |
| `InpMaxSpreadPoints` | 25 | Skip trading if spread is above this (0 = off) |
| `InpFastEMA` | 9 | Fast EMA period |
| `InpSlowEMA` | 21 | Slow EMA period |
| `InpRSIPeriod` | 14 | RSI period |
| `InpRSIBuyBelow` | 60 | Buy in an uptrend when RSI is below this |
| `InpRSISellAbove` | 40 | Sell in a downtrend when RSI is above this |
| `InpCandleLookback` | 10 | Number of recent candles measured for take profit |
| `InpTPCandleFactor` | 1.0 | Take profit = typical candle size × this |
| `InpSLtoTPRatio` | 2.5 | Stop loss = take profit distance × this |
| `InpUseBreakeven` | true | Move stop loss to breakeven after some profit |
| `InpBreakevenFrac` | 0.7 | Fraction of the way to take profit that triggers breakeven |
| `InpMaxRiskPct` | 10.0 | Skip a trade if stop loss risk exceeds this % of balance (0 = off) |
| `InpMaxDailyLossPct` | 10.0 | Stop opening trades for the day after losing this % (0 = off) |
| `InpShowDashboard` | true | Show the on-chart dashboard |

Raising `InpRSIBuyBelow` (for example to 70) and lowering `InpRSISellAbove` (for example to 30) makes the EA trade more often, with more risk.

## How the strategy works

1. On every new M5 candle, read the last closed candle's fast EMA, slow EMA and RSI.
2. If trend is up and RSI is below the buy limit, open a BUY. If trend is down and RSI is above the sell limit, open a SELL.
3. Set take profit from the typical candle size, and stop loss from the take profit distance times the ratio.
4. Before opening, check the spread, free margin, risk per trade and daily loss limit.
5. Manage the open trade, moving the stop to breakeven when the trigger is reached.

## Risk warning

Trading forex and CFDs carries a high risk of loss, and you can lose more than you expect. A wide stop loss with a small take profit means occasional losses are larger than typical wins. This software is provided for education and experimentation, with no warranty, and is not financial advice. **Test on a demo account first and never risk money you can't afford to lose.**

## Version history

- **v1.20 (ROBOTchattyV2):** take profit sized from candle size, wider stop loss ratio, breakeven based on take profit, trade logging in the Experts tab.
- **v1.10 (ROBOT chatty):** EMA + RSI entries with ATR-based stops, daily loss limit, on-chart dashboard.

## Author

Your name / GitHub username here.

## License

Choose a license (for example MIT) and add a `LICENSE` file to this repository.
