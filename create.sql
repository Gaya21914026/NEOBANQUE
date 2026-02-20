
CREATE TABLE customer (
    cust_id        INT PRIMARY KEY AUTO_INCREMENT,
    cust_name      VARCHAR(100) NOT NULL,
    cust_lastname  VARCHAR(100) NOT NULL,
    cust_phone     VARCHAR(12),
    cust_address   VARCHAR(255),
    cust_email     VARCHAR(150) UNIQUE,
    cust_active    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE account (
    acc_id        INT PRIMARY KEY AUTO_INCREMENT,
    acc_type      VARCHAR(50) NOT NULL,
    acc_balance   DECIMAL(15,2) NOT NULL DEFAULT 0,
    acc_currency  CHAR(3) NOT NULL DEFAULT 'EUR',
    acc_open      DATE NOT NULL,
    acc_close     DATE,
    acc_custid    INT NOT NULL,
    acc_active    BOOLEAN NOT NULL DEFAULT TRUE,


    CONSTRAINT fk_account_customer
        FOREIGN KEY (acc_custid) REFERENCES customer(cust_id),

    CONSTRAINT chk_balance_non_negative
        CHECK (acc_balance >= 0)
);
ALTER TABLE account ADD column transfer_limit DECIMAL(15,2) NOT NULL DEFAULT 5000;

CREATE TABLE bankcard (
    cb_id                 INT PRIMARY KEY AUTO_INCREMENT,
    cb_active             BOOLEAN NOT NULL DEFAULT TRUE,
    cb_num                VARCHAR(16) NOT NULL UNIQUE,
    cb_dateexp            DATE NOT NULL,
    cb_withdrawal_limit   DECIMAL(15),
    cb_payment_limit      DECIMAL(15),
    cb_accid              INT NOT NULL,
    
    CONSTRAINT fk_bankcard_account
        FOREIGN KEY (cb_accid) REFERENCES account(acc_id),
    
    CONSTRAINT chk_withdrawal_limit_non_negative
        CHECK (cb_withdrawal_limit >= 0),

    CONSTRAINT chk_payment_limit_non_negative
        CHECK (cb_payment_limit >= 0)
);


CREATE TABLE typetransaction (
    typtrans_id     BIGINT PRIMARY KEY AUTO_INCREMENT,
    typtrans_code   VARCHAR(30) NOT NULL UNIQUE,
    trans_lib       VARCHAR(100) NOT NULL,

    CONSTRAINT chk_typtrans_code
        CHECK (typtrans_code IN (
            'CREDIT',
            'DEBIT',
            'TRANSFER',
            'PAYMENT',
            'DEPOT'
        ))
);


CREATE TABLE transaction (
    trans_id           INT PRIMARY KEY AUTO_INCREMENT,
    trans_date         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    trans_amount       DECIMAL(15,2) NOT NULL CHECK (trans_amount > 0),
    trans_destaccid    INT,
    trans_sourceaccid  INT,
    trans_typtranscode VARCHAR(30) NOT NULL,


    CONSTRAINT fk_trans_dest_account
        FOREIGN KEY (trans_destaccid) REFERENCES account(acc_id),

    CONSTRAINT fk_trans_source_account
        FOREIGN KEY (trans_sourceaccid) REFERENCES account(acc_id),

    CONSTRAINT fk_trans_type
        FOREIGN KEY (trans_typtranscode) REFERENCES typetransaction(typtrans_code)
);

--add constratint to ensure that source and destination accounts in a transaction are not the same 
ALTER TABLE transaction
ADD CONSTRAINT chk_trans_accounts_different
CHECK (
    trans_destaccid IS NULL
    OR trans_sourceaccid IS NULL
    OR trans_destaccid <> trans_sourceaccid
);

ALTER TABLE transaction add column status ENUM('SUCCEEDED', 'FAILED') NOT NULL DEFAULT ('SUCCEEDED');

CREATE TABLE payment_cb (
    pcb_id        INT PRIMARY KEY AUTO_INCREMENT,
    pcb_cbid      INT NOT NULL,
    pcb_date      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    pcb_amount    DECIMAL(15,2) NOT NULL CHECK (pcb_amount > 0),
    pcb_lib       VARCHAR(150) NOT NULL,
    pcb_transid   INT NOT NULL,

    
    CONSTRAINT fk_paymentcb_card
        FOREIGN KEY (pcb_cbid) REFERENCES bankcard(cb_id),

    CONSTRAINT fk_paymentcb_transaction
        FOREIGN KEY (pcb_transid) REFERENCES transaction(trans_id)
);






CREATE TABLE banktransfert (
    bt_id             INT PRIMARY KEY AUTO_INCREMENT,
    bt_lib            VARCHAR(150) NOT NULL,
    bt_transiddebit   INT NOT NULL,
    bt_transidcredit  INT NOT NULL,

    CONSTRAINT fk_bt_trans_debit
        FOREIGN KEY (bt_transiddebit) REFERENCES transaction(trans_id),

    CONSTRAINT fk_bt_trans_credit
        FOREIGN KEY (bt_transidcredit) REFERENCES transaction(trans_id)
);


CREATE TABLE beneficiary (
    benef_id     INT PRIMARY KEY AUTO_INCREMENT,
    benef_accid  INT NOT NULL,
    benef_name   VARCHAR(150) NOT NULL,
    benef_custid INT NOT NULL,

    CONSTRAINT fk_benef_account
        FOREIGN KEY (benef_accid) REFERENCES account(acc_id),

    CONSTRAINT fk_benef_customer
        FOREIGN KEY (benef_custid) REFERENCES customer(cust_id)
);


CREATE TABLE auditlog (
    log_id       INT PRIMARY KEY AUTO_INCREMENT,
    log_type     VARCHAR(50) NOT NULL,
    log_table    VARCHAR(100) NOT NULL,
    log_cibleid  INT NOT NULL,
    log_custid   INT,
    log_date     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    log_detail   TEXT,

    CONSTRAINT fk_log_customer
        FOREIGN KEY (log_custid) REFERENCES customer(cust_id)
);


CREATE TABLE suspicious_transaction (
    st_id INT AUTO_INCREMENT PRIMARY KEY,
    st_transid INT NOT NULL,
    st_custid INT NOT NULL,
    st_reason VARCHAR(255) NOT NULL,
    st_risk_level ENUM('LOW', 'MEDIUM', 'HIGH') NOT NULL DEFAULT 'LOW',
    st_status ENUM('OPEN', 'PENDING', 'CLOSED') NOT NULL DEFAULT 'OPEN',
    st_created_at DATETIME NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_st_transid FOREIGN KEY (st_transid) REFERENCES transaction(trans_id),
    CONSTRAINT fk_st_custid FOREIGN KEY (st_custid) REFERENCES customer(cust_id)
);

--INDEX:
CREATE INDEX idx_account_custid ON account(acc_custid);
CREATE INDEX idx_card_accid ON bankcard(cb_accid);
CREATE INDEX idx_trans_dest ON transaction(trans_destaccid);
CREATE INDEX idx_trans_source ON transaction(trans_sourceaccid);
CREATE INDEX idx_pcb_transid ON payment_cb(pcb_transid);
CREATE INDEX idx_benef_accid ON beneficiary(benef_accid);
CREATE INDEX idx_customer_email ON customer(cust_email);
CREATE INDEX idx_account_active ON account(acc_active);
CREATE INDEX idx_trans_date ON transaction(trans_date);


