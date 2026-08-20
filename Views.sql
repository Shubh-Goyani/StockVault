-- 2.1 Portfolio summary: current holdings with unrealized P&L
CREATE OR REPLACE VIEW vw_portfolio_summary AS
SELECT
    h.INVESTOR_ID,
    s.SECURITY_ID,
    s.TICKER,
    s.COMPANY_NAME,
    s.SECURITY_TYPE,
    h.QUANTITY,
    h.AVG_COST_PRICE,
    h.CURRENT_VALUE,
    (h.QUANTITY * h.AVG_COST_PRICE)                        AS INVESTED_VALUE,
    h.CURRENT_VALUE - (h.QUANTITY * h.AVG_COST_PRICE)       AS UNREALIZED_PNL,
    CASE WHEN h.AVG_COST_PRICE > 0 THEN
        ROUND(((h.CURRENT_VALUE - (h.QUANTITY * h.AVG_COST_PRICE))
              / (h.QUANTITY * h.AVG_COST_PRICE)) * 100, 2)
    END                                                      AS UNREALIZED_PNL_PCT,
    h.LAST_UPDATED
FROM HOLDING h
JOIN SECURITY s ON s.SECURITY_ID = h.SECURITY_ID
WHERE h.QUANTITY > 0;
 
-- 2.2 KYC status per investor: doc counts by verification state
CREATE OR REPLACE VIEW vw_investor_kyc_status AS
SELECT
    i.INVESTOR_ID,
    i.FULL_NAME,
    i.KYC_STATUS                                            AS OVERALL_KYC_STATUS,
    COUNT(k.DOC_ID)                                          AS DOCS_SUBMITTED,
    COUNT(k.DOC_ID) FILTER (WHERE k.VERIFICATION_STATUS = 'VERIFIED')  AS DOCS_VERIFIED,
    COUNT(k.DOC_ID) FILTER (WHERE k.VERIFICATION_STATUS = 'PENDING')   AS DOCS_PENDING,
    COUNT(k.DOC_ID) FILTER (WHERE k.VERIFICATION_STATUS = 'REJECTED')  AS DOCS_REJECTED
FROM INVESTOR i
LEFT JOIN KYC_DOCUMENT k ON k.INVESTOR_ID = i.INVESTOR_ID
GROUP BY i.INVESTOR_ID, i.FULL_NAME, i.KYC_STATUS;
 
-- 2.3 Broker-client relationships with active plan pricing
CREATE OR REPLACE VIEW vw_broker_client_plans AS
SELECT
    bc.BC_ID,
    i.INVESTOR_ID,
    i.FULL_NAME                                             AS INVESTOR_NAME,
    b.BROKER_ID,
    b.FULL_NAME                                             AS BROKER_NAME,
    bc.PLAN_TYPE,
    pc.BROKERAGE_PERCENT,
    bc.PLAN_START_DATE,
    bc.PLAN_END_DATE,
    bc.POA_GRANTED,
    CASE
        WHEN bc.PLAN_END_DATE IS NULL OR bc.PLAN_END_DATE >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                                                      AS PLAN_IS_CURRENT
FROM BROKER_CLIENT bc
JOIN INVESTOR i ON i.INVESTOR_ID = bc.INVESTOR_ID
JOIN BROKER b ON b.BROKER_ID = bc.BROKER_ID
LEFT JOIN PLAN_CATALOG pc ON pc.PLAN_TYPE = bc.PLAN_TYPE
WHERE bc.IS_ACTIVE = TRUE;
 
-- 2.4 Order execution detail: ordered vs filled vs remaining quantity
CREATE OR REPLACE VIEW vw_order_execution_detail AS
SELECT
    o.ORDER_ID,
    o.TA_ID,
    o.SECURITY_ID,
    s.TICKER,
    o.SIDE,
    o.ORDER_TYPE,
    o.QUANTITY                                              AS ORDERED_QTY,
    COALESCE(SUM(t.FILLED_QTY), 0)                          AS FILLED_QTY,
    o.QUANTITY - COALESCE(SUM(t.FILLED_QTY), 0)             AS REMAINING_QTY,
    o.STATUS,
    o.PLACED_AT,
    COALESCE(SUM(t.NET_AMOUNT), 0)                          AS TOTAL_NET_AMOUNT
FROM ORDER_RECORD o
JOIN SECURITY s ON s.SECURITY_ID = o.SECURITY_ID
LEFT JOIN TRADE t ON t.ORDER_ID = o.ORDER_ID
GROUP BY o.ORDER_ID, o.TA_ID, o.SECURITY_ID, s.TICKER, o.SIDE,
         o.ORDER_TYPE, o.QUANTITY, o.STATUS, o.PLACED_AT;
 
-- 2.5 Capital gains with STCG/LTCG classification
-- (India rule of thumb: equity held > 365 days = long-term)
CREATE OR REPLACE VIEW vw_capital_gains_report AS
SELECT
    cg.CG_ID,
    tr_buy.ORDER_ID                                         AS BUY_ORDER_ID,
    tr_sell.ORDER_ID                                        AS SELL_ORDER_ID,
    o.TA_ID,
    ta.INVESTOR_ID,
    s.TICKER,
    cg.QUANTITY,
    cg.BUY_PRICE,
    cg.SELL_PRICE,
    (cg.SELL_PRICE - cg.BUY_PRICE) * cg.QUANTITY            AS GROSS_GAIN,
    cg.HOLDING_DAYS,
    CASE WHEN cg.HOLDING_DAYS > 365 THEN 'LTCG' ELSE 'STCG' END AS GAIN_TYPE,
    cg.TAX_AMOUNT
FROM CAPITAL_GAINS_RECORD cg
JOIN TRADE tr_buy  ON tr_buy.TRADE_ID = cg.BUY_TRADE_ID
JOIN TRADE tr_sell ON tr_sell.TRADE_ID = cg.SELL_TRADE_ID
JOIN ORDER_RECORD o ON o.ORDER_ID = tr_sell.ORDER_ID
JOIN TRADING_ACC ta ON ta.TA_ID = o.TA_ID
JOIN SECURITY s ON s.SECURITY_ID = o.SECURITY_ID;
