-- WAK-OPS-010: Executive FinOps Ledger
-- Objective: Real-time unit economics by service for ExCo leadership

SELECT 
  line_item_product_code as Service, 
  sum(line_item_unblended_cost) as Total_Spend,
  sum(usage_quantity) as Total_Usage,
  pricing_unit as Unit
FROM "wakwetu_finops_db"."wakwetu_billing_data"
WHERE line_item_usage_start_date >= now() - interval '30' day
GROUP BY 1, 4
ORDER BY 2 DESC;
