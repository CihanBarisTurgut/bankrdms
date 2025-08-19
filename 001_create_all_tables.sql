CREATE TABLE IF NOT EXISTS customer (
        customer_id SERIAL PRIMARY KEY,
        customer_name VARCHAR(100) NOT NULL,
        tc_no CHAR(11) NOT NULL UNIQUE,
        birth_date DATE NOT NULL,
        birth_place VARCHAR(50) NOT NULL,
        risk_limit DECIMAL(10,2) DEFAULT 10000.00,
        deleted_at TIMESTAMP DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE IF NOT EXISTS account (
        account_id SERIAL PRIMARY KEY,
        customer_id INT NOT NULL,
        iban CHAR(26) NOT NULL UNIQUE,
        account_name VARCHAR(50) NOT NULL,
        status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
        deleted_at TIMESTAMP DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
    );
    
CREATE TABLE IF NOT EXISTS card_type (
        card_type_id SERIAL PRIMARY KEY,
        type_name VARCHAR(50) NOT NULL UNIQUE,
        description VARCHAR(100) NULL
    );

CREATE TABLE IF NOT EXISTS card (
        card_id SERIAL PRIMARY KEY,
        customer_id INT NOT NULL,
        account_id INT NULL,
        card_type_id INT NOT NULL,
        card_number CHAR(16) NOT NULL UNIQUE,
        expiry_month SMALLINT NOT NULL,
        expiry_year SMALLINT NOT NULL,
        ccv VARCHAR(3) NOT NULL,
        limit_amount DECIMAL(13,3) DEFAULT NULL, -- Kredi kartı için
        current_debt DECIMAL(13,3) DEFAULT NULL, -- Kredi kartı için
		balance DECIMAL(13,3) DEFAULT 0, -- Hesap kartı için
        status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
        deleted_at TIMESTAMP DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(customer_id) REFERENCES customer(customer_id),
        FOREIGN KEY(account_id) REFERENCES account(account_id),
        FOREIGN KEY(card_type_id) REFERENCES card_type(card_type_id)
    );
    
CREATE TABLE IF NOT EXISTS transaction_type (
        transaction_type_id SERIAL PRIMARY KEY,
        type_name VARCHAR(50) NOT NULL UNIQUE
    );

CREATE TABLE IF NOT EXISTS transaction (
        transaction_id SERIAL PRIMARY KEY,
        card_id INT NOT NULL,
        transaction_type_id INT NOT NULL,
        description VARCHAR(100),
        amount DECIMAL(13,3) NOT NULL,
        transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(card_id) REFERENCES card(card_id),
        FOREIGN KEY(transaction_type_id) REFERENCES transaction_type(transaction_type_id)
    );

CREATE TABLE IF NOT EXISTS audit_log (
        audit_id SERIAL PRIMARY KEY,
        table_name VARCHAR(50) NOT NULL,
        operation_type VARCHAR(20) NOT NULL CHECK (operation_type IN ('INSERT','UPDATE','DELETE','SOFT_DELETE')),
        record_id INT NOT NULL,
        old_data JSONB DEFAULT NULL,
        new_data JSONB DEFAULT NULL,
        performed_by VARCHAR(100) DEFAULT CURRENT_USER,
        performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
