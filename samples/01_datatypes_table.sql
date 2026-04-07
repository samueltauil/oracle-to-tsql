-- Test file: Oracle data types → T-SQL data type mapping
-- Covers all major Oracle types that require conversion

CREATE TABLE employees (
    employee_id       NUMBER(10)          NOT NULL,
    first_name        VARCHAR2(50),
    last_name         VARCHAR2(100)       NOT NULL,
    email             NVARCHAR2(200),
    phone_number      VARCHAR2(20),
    hire_date         DATE                NOT NULL,
    salary            NUMBER(10,2),
    commission_pct    NUMBER(4,2),
    department_id     NUMBER(5),
    is_active         NUMBER(1)           DEFAULT 1,
    notes             CLOB,
    photo             BLOB,
    resume            NCLOB,
    badge_raw         RAW(16),
    created_at        TIMESTAMP           DEFAULT SYSTIMESTAMP,
    updated_at        TIMESTAMP WITH TIME ZONE,
    yearly_bonus      BINARY_FLOAT,
    lifetime_value    BINARY_DOUBLE,
    metadata          XMLTYPE,
    legacy_desc       LONG,
    CONSTRAINT pk_employees PRIMARY KEY (employee_id),
    CONSTRAINT uq_employees_email UNIQUE (email),
    CONSTRAINT chk_salary CHECK (salary > 0),
    CONSTRAINT fk_dept FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
);

CREATE SEQUENCE emp_seq START WITH 1000 INCREMENT BY 1 NOCACHE NOCYCLE;

CREATE INDEX idx_emp_dept ON employees(department_id);
CREATE INDEX idx_emp_hire ON employees(hire_date);
CREATE INDEX idx_emp_name ON employees(last_name, first_name);
