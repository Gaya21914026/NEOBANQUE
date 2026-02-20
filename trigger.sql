-- Trigger to prevent negative balance in account
CREATE TRIGGER trg_no_negative_balance
BEFORE UPDATE ON account
FOR EACH ROW
BEGIN
    IF NEW.acc_balance < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Balance cannot be negative.';
    END IF;
END;


--Log balance changes in auditlog
CREATE TRIGGER trg_balance_change
AFTER UPDATE ON account
FOR EACH ROW
BEGIN
    IF NEW.acc_balance <> OLD.acc_balance THEN
        INSERT INTO auditlog (log_type, log_table, log_cibleid, log_custid, log_detail) VALUES ('BALANCE_CHANGE','account', NEW.acc_id,NEW.acc_custid,CONCAT('Balance changed from ', OLD.acc_balance, ' to ', NEW.acc_balance));
    END IF;
END;

--close suspicious transaction if related transaction fails
CREATE TRIGGER trg_close_suspicion_on_failed
AFTER UPDATE ON transaction
FOR EACH ROW
BEGIN
    IF NEW.status = 'FAILED' THEN
        UPDATE suspicious_transaction
        SET st_status = 'CLOSED'
        WHERE st_transid = NEW.trans_id
          AND st_status = 'OPEN';
    END IF;
END;

--Do not delete transactions
CREATE TRIGGER trg_no_delete_transaction
BEFORE DELETE ON transaction
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Deleting transactions is not allowed.';
END;
