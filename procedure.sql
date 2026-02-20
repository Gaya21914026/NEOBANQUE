-- EFFECTUE UN PAIEMENT CB EN :
-------   EFFECTUANT LES VERIFICATIONS D'USAGE (CARTE ACTIVE, SOLDE SUFFISANT, CARTE EXISTANTE),
-------   DEBITANT LE COMPTE LIE A LA CARTE, 
-------   ENREGISTRE LA TRANSACTION (PEU IMPORTE LE STATUT DU PAIEMENT),
-------   ENREGISTRE LE PAIEMENT SI LA TRANSACTION EST REUSSIE
-------   LOGUE L'OPERATION DANS LA TABLE AUDITLOG

DROP PROCEDURE IF EXISTS do_payment_cb;
CREATE PROCEDURE do_payment_cb(
    IN pay_cbid INT,
    IN pay_amount DECIMAL(15,2),
    IN pay_lib VARCHAR(150)
 )
BEGIN
    DECLARE accid INT;
    DECLARE custid INT;
    DECLARE balance DECIMAL(15,2);
    DECLARE last_transid INT;

    START TRANSACTION;

    IF (SELECT cb_active FROM bankcard WHERE cb_id = pay_cbid) = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Card is inactive.';
    END IF;

    IF (SELECT COUNT(*) FROM bankcard WHERE cb_id = pay_cbid) = 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Carte inexistante.';
    END IF;


    SELECT cb_accid INTO accid
    FROM bankcard
    WHERE cb_id = pay_cbid;

    SELECT acc_balance INTO balance
    FROM account
    WHERE acc_id = accid;

    SELECT acc_custid INTO custid
    FROM account
    WHERE acc_id = accid;

    IF balance < pay_amount THEN

        INSERT INTO `transaction`(trans_amount, trans_destaccid, trans_sourceaccid, trans_typtranscode,status) VALUES (pay_amount, NULL, accid, 'DEBIT','FAILED');
        INSERT INTO auditlog (log_type, log_table, log_cibleid, log_custid, log_detail) VALUES ('PAYMENT', 'payment_cb', LAST_INSERT_ID(), custid, pay_lib);
        COMMIT;

        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient balance.';
        
        
        
    END IF;

    UPDATE account
    SET acc_balance = acc_balance - pay_amount
    WHERE acc_id = accid;

    INSERT INTO `transaction`
        (trans_amount, trans_destaccid, trans_sourceaccid, trans_typtranscode,status)
    VALUES
        (pay_amount, NULL, accid, 'DEBIT','SUCCEEDED');

    SET last_transid = LAST_INSERT_ID();

    INSERT INTO payment_cb
        (pcb_cbid, pcb_amount, pcb_lib, pcb_transid)
    VALUES
        (pay_cbid, pay_amount, pay_lib, last_transid);

    INSERT INTO auditlog
        (log_type, log_table, log_cibleid, log_custid, log_detail)
    VALUES
        ('PAYMENT', 'payment_cb', LAST_INSERT_ID(), custid, pay_lib);

    COMMIT;
END;


--EXEMPLES D'APPEL DE LA PROCEDURE DE PAIEMENT CB
CALL do_payment_cb(1, 50.01, 'test procedure');
CALL do_payment_cb(1, 500000.00, 'test procedure with insufficient balance');
CALL do_payment_cb(1000, 50.01, 'test procedure with innexistant  card');
select * from transaction;



-- EFFECTUE VIREMENT EN :
-------   EFFECTUANT LES VERIFICATIONS D'USAGE (COMPTES EXISTANTS, COMPTES DIFFERENTS, PLAFOND, SOLDE SUFFISANT...), 
-------   > 3 TRANSACTIONS SUSPECTE DU COMPTE --> RISQUE ELEVE,BLOCKAGE DU VIREMENT,INSERTION DANS TRANSACTION ET AUDITLOG LES RAISONS DU BLOCKAGE
-------   > MOYENNE DES VIREMENTS DES 3 DERNIERS MOIS INHABITUELLE --> EFFECTUE LE VIREMENT MAIS INSERE UNE TRANSACTION SUSPECTE DE RISQUE MOYEN AVEC RAISON DANS LA TABLE SUSPICIOUS_TRANSACTION
-------   > 5 TRANSACTIONS DANS LES 10 DERNIERES MINUTES (DE TYPE "-") --> RISQUE ELEVE,BLOCKAGE DU VIREMENT,INSERTION DANS TRANSACTION ET AUDITLOG LES RAISONS DU BLOCKAGE
-------   SI LE VIREMENT EST EFFECTUE:
-------------  UPDATE DES SOLDES DES COMPTES SOURCE ET DESTINATION,
-------------  INSERTION DE 2 TRANSACTIONS (DEBIT ET CREDIT),   
-------------  INSERTION DANS LA TABLE BANKTRANSFERT,
-------------  INSERTION DANS LA TABLE AUDITLOG
-------------   SI RISQUE MOYEN OU FAIBLE --> INSERTION DANS LA TABLE SUSPICIOUS_TRANSACTION AVEC RAISON
-------   SI LE VIREMENT EST BLOQUE:
-------------  INSERTION DANS LA TABLE SUSPICIOUS_TRANSACTION AVEC RAISON


DROP PROCEDURE IF EXISTS internal_transfer;
CREATE PROCEDURE internal_transfer(
    IN p_source_accid INT,
    IN p_dest_accid   INT,
    IN p_amount       DECIMAL(15,2),
    IN p_custid       INT,
    IN p_reason       VARCHAR(255)
)
BEGIN
    DECLARE v_src_balance        DECIMAL(15,2);
    DECLARE v_daily_total        DECIMAL(15,2);
    DECLARE v_avg_amount_3m     DECIMAL(15,2);
    DECLARE v_transid_debit      INT;
    DECLARE v_transid_credit     INT;
    DECLARE v_src_custid         INT;
    DECLARE v_dest_custid        INT;
    DECLARE v_open_susp_accounts INT;
    DECLARE v_rb_transfers   INT;
    DECLARE v_is_high_risk       BOOLEAN DEFAULT FALSE;
    DECLARE v_is_medium_risk     BOOLEAN DEFAULT FALSE;
    DECLARE v_is_low_risk        BOOLEAN DEFAULT FALSE;
    DECLARE v_reason_text        VARCHAR(255) DEFAULT '';
    DECLARE v_src_active BOOLEAN;
    DECLARE v_dest_active BOOLEAN;
    DECLARE v_transfer_limit DECIMAL(15,2);
    DECLARE v_negartive_recent_transfers INT;

    -- check amount > 0
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid transfer amount. Amount must be greater than zero.';
    END IF;

    -- check different
    IF p_source_accid = p_dest_accid THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Source and destination accounts must be different.';
    END IF;

    -- check accounts existence, active and get source account balance and transfer limit
    SELECT acc_custid, acc_active, acc_balance, transfer_limit
    INTO v_src_custid, v_src_active, v_src_balance, v_transfer_limit
    FROM account
    WHERE acc_id = p_source_accid;

    IF v_src_custid IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Source account does not exist.';
    END IF;

    IF v_src_active = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Inactive source account.';
    END IF;

    SELECT acc_custid, acc_active
    INTO v_dest_custid, v_dest_active
    FROM account
    WHERE acc_id = p_dest_accid;

    IF v_dest_custid IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Destination account does not exist.';
    END IF;

    IF v_dest_active = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Inactive destination account.';
    END IF;

    -- check balance
    IF v_src_balance < p_amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient balance to do the transfer.';
    END IF;

    -- check transfer limit
    IF p_amount > v_transfer_limit THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transfer amount exceeds the transfer limit.';
    END IF;

    -- suspicious activity on source account
    SELECT COUNT(*)
    INTO v_open_susp_accounts
    FROM suspicious_transaction st
    JOIN transaction t ON t.trans_id = st.st_transid
    WHERE st.st_status = 'OPEN'
      AND (t.trans_sourceaccid = p_source_accid OR t.trans_destaccid = p_source_accid);

    
    IF v_open_susp_accounts >= 3 THEN
        SET v_is_high_risk = TRUE;
        SET v_reason_text = CONCAT(v_reason_text,'   source account has multiple open suspicious transactions.');
    END IF;

    -- inusual transfer amount compared to average of last 3 months
    SELECT AVG(trans_amount)
    INTO v_avg_amount_3m
    FROM transaction
    WHERE trans_sourceaccid = p_source_accid
      AND trans_date >= DATE_SUB(NOW(), INTERVAL 3 MONTH)
      AND trans_typtranscode IN ('DEBIT', 'TRANSFER');

    IF v_avg_amount_3m IS NOT NULL AND p_amount > v_avg_amount_3m  THEN
        SET v_is_medium_risk = TRUE;
        IF v_reason_text IS NULL THEN
            SET v_reason_text = CONCAT(v_reason_text, ' inhabitual transfer amount compared to average of last 3 months.');
        END IF;
    END IF;

    -- transfers frequency in last 10 minutes
    SELECT COUNT(*)
    INTO v_negartive_recent_transfers
    FROM transaction
    WHERE trans_sourceaccid = p_source_accid
      AND trans_typtranscode IN ('DEBIT', 'TRANSFER')
      AND trans_date >= DATE_SUB(NOW(), INTERVAL 10 MINUTE);

    IF v_negartive_recent_transfers > 5 THEN
        SET v_is_high_risk = TRUE;
        IF v_reason_text IS NULL THEN
            SET v_reason_text = CONCAT(v_reason_text, '     high frequency of transactions in the last 10 minutes.');
        END IF;
    END IF;


    -- Block transfer if high risk and log the reason
    IF v_is_high_risk = TRUE THEN
        

        INSERT INTO transaction ( trans_amount, trans_destaccid, trans_sourceaccid, trans_typtranscode, status ) VALUES ( p_amount, p_dest_accid, p_source_accid, 'DEBIT', 'FAILED' );
        SET v_transid_debit = LAST_INSERT_ID();
        
        INSERT INTO transaction ( trans_amount, trans_destaccid, trans_sourceaccid, trans_typtranscode, status ) VALUES ( p_amount, p_dest_accid, p_source_accid, 'CREDIT', 'FAILED' );
        SET v_transid_credit = LAST_INSERT_ID();

        INSERT INTO suspicious_transaction ( st_transid, st_custid, st_reason, st_risk_level, st_status ) VALUES ( v_transid_debit, p_custid, v_reason_text, 'HIGH', 'OPEN' );
        SET v_reason_text = CONCAT('Transfer blocked due to high risk of fraud. ', v_reason_text);
        
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = v_reason_text;
    END IF;

    START TRANSACTION;

    -- update source account balance
    UPDATE account
    SET acc_balance = acc_balance - p_amount
    WHERE acc_id = p_source_accid;

    -- update destination account balance
    UPDATE account
    SET acc_balance = acc_balance + p_amount
    WHERE acc_id = p_dest_accid;

    -- insert transaction DEBIT
    INSERT INTO transaction (trans_amount, trans_destaccid, trans_sourceaccid, trans_typtranscode, status)
    VALUES (p_amount, p_dest_accid, p_source_accid, 'DEBIT', 'SUCCEEDED');

    SET v_transid_debit = LAST_INSERT_ID();

    -- insert transaction CREDIT
    INSERT INTO transaction (trans_amount, trans_destaccid, trans_sourceaccid, trans_typtranscode, status)
    VALUES (p_amount, p_dest_accid, p_source_accid, 'CREDIT', 'SUCCEEDED');

    SET v_transid_credit = LAST_INSERT_ID();

    -- insert banktransfert
    INSERT INTO banktransfert (bt_lib, bt_transiddebit, bt_transidcredit)
    VALUES (p_reason, v_transid_debit, v_transid_credit);

    -- insert audit log for the transfer
    INSERT INTO auditlog (log_type, log_table, log_cibleid, log_custid, log_detail) VALUES ('INTERNAL_TRANSFER','banktransfert',LAST_INSERT_ID(),p_custid,CONCAT('Virement interne de ', p_amount, ' EUR du compte ',p_source_accid, ' vers ', p_dest_accid,'. Motif : ', p_reason));

    -- create suspicious transaction if medium or low risk
    IF v_is_low_risk = TRUE OR v_is_medium_risk = TRUE THEN
        INSERT INTO suspicious_transaction (st_transid, st_custid, st_reason, st_risk_level, st_status)
        VALUES (v_transid_debit, p_custid, COALESCE(v_reason_text, 'potential risk detected for this transfer'),
            CASE
                WHEN v_is_medium_risk = TRUE THEN 'MEDIUM'
                ELSE 'LOW'
            END,
            'OPEN'
        );
    END IF;

    COMMIT;
END;

CALL internal_transfer(1, 3, 10, 1, 'Test virement OK');
CALL internal_transfer(1, 3, 0, 1, 'Test zero amount');
CALL internal_transfer(1, 1, 10, 1, 'Test Same account');
CALL internal_transfer(1, 3, 999999, 1, 'Test Insufficient balance');
UPDATE account SET transfer_limit = 50 WHERE acc_id = 1;
CALL internal_transfer(1, 3, 100, 1, 'Test transfer limit exceeded');