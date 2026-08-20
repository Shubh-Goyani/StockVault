--1. Fetch Active Securities in a Specific Exchange
SELECT s.TICKER, s.COMPANY_NAME, s.SECURITY_TYPE, e.MARKET_CAP
FROM trading.SECURITY s
JOIN trading.EQUITY e ON s.SECURITY_ID = e.SECURITY_ID
WHERE s.EXCHANGE = 'NSE' AND s.IS_ACTIVE = TRUE;

--2. Lists investors whose KYC is pending along with any documents they've uploaded.
SELECT 
    i.INVESTOR_ID,
    i.FULL_NAME,
    i.KYC_STATUS,
    k.DOC_TYPE,
    k.DOC_NO,
    k.VERIFICATION_STATUS
FROM INVESTOR i
LEFT JOIN KYC_DOCUMENT k ON i.INVESTOR_ID = k.INVESTOR_ID
WHERE i.KYC_STATUS = 'PENDING'
ORDER BY i.CREATED_AT;

--3. Finds registered investors who currently own no securities.
SELECT i.investor_id,
       i.full_name
FROM investor i
LEFT JOIN holding h
ON i.investor_id = h.investor_id
WHERE h.holding_id IS NULL;

--4. Fund transaction summary
SELECT
       txn_type,
       COUNT(*) AS total_transactions,
       SUM(amt) AS total_amount
FROM fund_transaction
GROUP BY txn_type;

--5. Find investors with the highest portfolio value.

SELECT i.investor_id,
       i.full_name,
       ROUND(SUM(h.current_value), 2) AS portfolio_value
FROM investor i
JOIN holding h
ON i.investor_id = h.investor_id
GROUP BY i.investor_id, i.full_name
ORDER BY portfolio_value DESC
LIMIT 10;

--6. Shows the most actively traded stocks.
SELECT s.ticker,
       s.company_name,
       COUNT(o.order_id) AS total_orders
FROM security s
LEFT JOIN order_record o
ON s.security_id = o.security_id
GROUP BY s.security_id, s.ticker, s.company_name
ORDER BY total_orders DESC
LIMIT 10;

--7. Shows each investor's live holdings with unrealized profit/loss.
SELECT 
    i.FULL_NAME,
    s.TICKER,
    s.COMPANY_NAME,
    h.QUANTITY,
    h.AVG_COST_PRICE,
    h.CURRENT_VALUE,
    ROUND(h.CURRENT_VALUE - (h.QUANTITY * h.AVG_COST_PRICE), 2) AS UNREALIZED_PNL
FROM INVESTOR i
JOIN HOLDING h ON i.INVESTOR_ID = h.INVESTOR_ID
JOIN SECURITY s ON h.SECURITY_ID = s.SECURITY_ID
WHERE i.IS_ACTIVE = TRUE
ORDER BY i.FULL_NAME, UNREALIZED_PNL DESC;

--8. Measures broker performance based on brokerage earned.
SELECT b.broker_id,
       b.full_name,
       ROUND(SUM(t.brokerage_fee), 2) AS brokerage_revenue
FROM broker b
JOIN order_record o
ON b.broker_id = o.broker_id
JOIN trade t
ON o.order_id = t.order_id
GROUP BY b.broker_id, b.full_name
ORDER BY brokerage_revenue DESC;

--9. Brokerage Revenue per Broker (Last 3 Months)
SELECT 
    b.BROKER_ID,
    b.FULL_NAME,
    b.SEBI_LICENSE_NO,
    COALESCE(SUM(t.BROKERAGE_FEE), 0) AS total_brokerage
FROM BROKER b
LEFT JOIN ORDER_RECORD o ON b.BROKER_ID = o.BROKER_ID
LEFT JOIN TRADE t ON o.ORDER_ID = t.ORDER_ID 
   AND t.TRADE_DATETIME >= NOW() - INTERVAL '3 months'
GROUP BY b.BROKER_ID, b.FULL_NAME, b.SEBI_LICENSE_NO
ORDER BY total_brokerage DESC;

--10. Top 10 Most Traded Securities (Last 30 Days)
SELECT 
    s.SECURITY_ID,
    s.TICKER,
    s.COMPANY_NAME,
    s.EXCHANGE,
    SUM(t.FILLED_QTY) AS total_qty_traded
FROM SECURITY s
JOIN ORDER_RECORD o ON s.SECURITY_ID = o.SECURITY_ID
JOIN TRADE t ON o.ORDER_ID = t.ORDER_ID
WHERE t.TRADE_DATETIME >= NOW() - INTERVAL '1 month'
GROUP BY s.SECURITY_ID, s.TICKER, s.COMPANY_NAME, s.EXCHANGE
ORDER BY total_qty_traded DESC
LIMIT 10;

--11. Average Order Execution Time per Broker
SELECT 
    b.BROKER_ID,
    b.FULL_NAME,
    ROUND(AVG(EXTRACT(EPOCH FROM (t.TRADE_DATETIME - o.PLACED_AT)) / 60), 1) AS avg_exec_minutes
FROM BROKER b
JOIN ORDER_RECORD o ON b.BROKER_ID = o.BROKER_ID
JOIN TRADE t ON o.ORDER_ID = t.ORDER_ID
GROUP BY b.BROKER_ID, b.FULL_NAME
ORDER BY avg_exec_minutes;

--12. all mutual funds whose internal expense ratios exceed the baseline average of their specific asset category
SELECT s.COMPANY_NAME, m.AMC_NAME, m.SCHEME_CATEGORY, m.EXPENSE_RATIO, m.NAV
FROM trading.MUTUAL_FUND m
JOIN trading.SECURITY s ON m.SECURITY_ID = s.SECURITY_ID
WHERE m.EXPENSE_RATIO > (
    SELECT AVG(sub_m.EXPENSE_RATIO)
    FROM trading.MUTUAL_FUND sub_m
    WHERE sub_m.SCHEME_CATEGORY = m.SCHEME_CATEGORY
)

--13. Filters down whose portfolios are dangerously concentrated in only two or fewer asset types.
SELECT i.INVESTOR_ID, i.FULL_NAME, i.RISK_PROFILE,
       COUNT(h.HOLDING_ID) AS total_unique_assets,
       SUM(h.CURRENT_VALUE) AS global_portfolio_worth
FROM trading.INVESTOR i
JOIN trading.HOLDING h ON i.INVESTOR_ID = h.INVESTOR_ID
WHERE i.INVESTOR_TYPE = 'RETAIL' 
  AND i.RISK_PROFILE IN ('AGGRESSIVE', 'HNI')
GROUP BY i.INVESTOR_ID, i.FULL_NAME, i.RISK_PROFILE
HAVING COUNT(h.HOLDING_ID) <= 2 AND SUM(h.CURRENT_VALUE) > 500000
ORDER BY global_portfolio_worth DESC;

--14. Classifies each realized gain as Short-Term (≤365 days) or Long-Term for tax reporting.
SELECT 
    i.FULL_NAME,
    s.TICKER,
    cg.QUANTITY,
    cg.BUY_PRICE,
    cg.SELL_PRICE,
    ROUND((cg.SELL_PRICE - cg.BUY_PRICE) * cg.QUANTITY, 2) AS GAIN_LOSS,
    CASE 
        WHEN cg.HOLDING_DAYS <= 365 THEN 'SHORT_TERM'
        ELSE 'LONG_TERM'
    END AS GAIN_TYPE,
    cg.TAX_AMOUNT
FROM CAPITAL_GAINS_RECORD cg
JOIN TRADE t_buy ON cg.BUY_TRADE_ID = t_buy.TRADE_ID
JOIN ORDER_RECORD o ON t_buy.ORDER_ID = o.ORDER_ID
JOIN TRADING_ACC ta ON o.TA_ID = ta.TA_ID
JOIN INVESTOR i ON ta.INVESTOR_ID = i.INVESTOR_ID
JOIN SECURITY s ON o.SECURITY_ID = s.SECURITY_ID
ORDER BY GAIN_LOSS DESC;

--15. Track High-Slippage Stop-Loss Orders
(Targets the ORDER_RECORD database to isolate all Stop-Loss (SL) orders that were cancelled before getting executed, 
helping look for system latency or market dropouts.)
SELECT ORDER_ID, SECURITY_ID, SIDE, QUANTITY, STOP_LOSS_PRICE, STATUS
FROM trading.ORDER_RECORD
WHERE ORDER_TYPE = 'SL' 
  AND STATUS = 'CANCELLED';
