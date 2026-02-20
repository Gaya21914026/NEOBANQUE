--Top 10 Clients par volume total de transactions ou montants déposés.

WITH client_activity AS (
    SELECT a.acc_custid AS cust_id, COUNT(t.trans_id) AS nb_transactions
    FROM transaction t
    JOIN account a ON a.acc_id = t.trans_sourceaccid
    GROUP BY a.acc_custid
)
SELECT  c.cust_id, c.cust_name, c.cust_lastname, ca.nb_transactions, 
DENSE_RANK() OVER (ORDER BY ca.nb_transactions DESC) AS rank_activity 
FROM customer c 
JOIN client_activity ca ON ca.cust_id = c.cust_id 
ORDER BY nb_transactions DESC 
LIMIT 10;

--Transactions Suspectes Détection basée sur des règles  prédéfinies ou des seuils d'activité.

WITH suspicious AS (
    SELECT t.trans_id, t.trans_sourceaccid, t.trans_amount, t.trans_date,
        CASE 
            WHEN t.trans_amount > 10000 THEN 'HIGH'
            WHEN t.trans_amount > 5000 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS risk_level
    FROM transaction t
)
SELECT *
FROM suspicious
WHERE risk_level IN ('MEDIUM', 'HIGH')
ORDER BY trans_amount DESC;

--Évolution des Dépôts Analyse mensuelle des volumes et  fréquences de dépôts
WITH monthly_depot AS (
    SELECT DATE_FORMAT(t.trans_date, '%Y-%m') AS month, SUM(t.trans_amount) AS total_depot, COUNT(*) AS nb_depot
    FROM transaction t
    WHERE t.trans_typtranscode IN ('CREDIT', 'DEPOT')
    GROUP BY DATE_FORMAT(t.trans_date, '%Y-%m')
),
evolution AS (
    SELECT month, total_depot, nb_depot, LAG(total_depot) OVER (ORDER BY month) AS old_total, LAG(nb_depot) OVER (ORDER BY month) AS old_count
    FROM monthly_depot
)
SELECT month, total_depot, nb_depot, (total_depot - old_total) AS diff_montant, (nb_depot - old_count) AS diff_nbr
FROM evolution
ORDER BY month;

--Classement des Comptes Par activité (nombre de transactions) ou  solde moyen
WITH account_activity AS (
    SELECT t.trans_sourceaccid AS acc_id, COUNT(*) AS nb_transactions
    FROM transaction t
    GROUP BY t.trans_sourceaccid
)
SELECT a.acc_id, a.acc_custid, act.nb_transactions, 
    DENSE_RANK() OVER (ORDER BY act.nb_transactions DESC) AS rank_activity
FROM account a
JOIN account_activity act ON act.acc_id = a.acc_id
ORDER BY nb_transactions DESC;
