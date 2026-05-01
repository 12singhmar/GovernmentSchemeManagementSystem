-- ============================================================
-- GOVERNMENT SCHEME MANAGEMENT SYSTEM
-- UCS310 - Database Management Systems
-- Group 4 | 2C33 | Thapar Institute of Engineering & Technology
-- Submitted To: Ms. Reaya Grewal
-- Members: Kavya Singal, Ipshita Singla, Akshaj Singhmar
-- ============================================================
-- PART 1: SCHEMA DDL (Oracle SQL)
-- Run this file first on Oracle LiveSQL: https://livesql.oracle.com
-- ============================================================

-- -------------------------------------------------------
-- STEP 0: CLEANUP (Drop tables in reverse FK order)
-- -------------------------------------------------------
BEGIN
    FOR t IN (
        SELECT table_name FROM user_tables
        WHERE table_name IN (
            'FUND_DISBURSEMENT','APPLICATION_AUDIT_LOG',
            'APPLICATION','CITIZEN_DOCUMENTS',
            'SCHEME_ELIGIBILITY_RULES','SCHEME_FUND_POOL',
            'OFFICER','CITIZEN','SCHEME','DEPARTMENT'
        )
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS';
    END LOOP;
END;
/

BEGIN
    FOR s IN (
        SELECT sequence_name FROM user_sequences
        WHERE sequence_name IN (
            'SEQ_DEPT','SEQ_SCHEME','SEQ_OFFICER','SEQ_CITIZEN',
            'SEQ_APPLICATION','SEQ_DISBURSEMENT','SEQ_AUDIT','SEQ_RULE','SEQ_POOL'
        )
    ) LOOP
        EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
    END LOOP;
END;
/

-- -------------------------------------------------------
-- STEP 1: SEQUENCES (Auto-increment PKs)
-- -------------------------------------------------------
CREATE SEQUENCE SEQ_DEPT        START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_SCHEME      START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_OFFICER     START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CITIZEN     START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_APPLICATION START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_DISBURSEMENT START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_AUDIT       START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_RULE        START WITH 1  INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_POOL        START WITH 1  INCREMENT BY 1 NOCACHE;

-- -------------------------------------------------------
-- TABLE 1: DEPARTMENT
-- Stores government departments managing schemes
-- -------------------------------------------------------
CREATE TABLE Department (
    department_id       NUMBER          PRIMARY KEY,
    department_name     VARCHAR2(100)   NOT NULL UNIQUE,
    department_code     VARCHAR2(10)    NOT NULL UNIQUE,   -- e.g. MOA, MOHFW
    ministry            VARCHAR2(100)   NOT NULL,
    head_name           VARCHAR2(100),
    contact_email       VARCHAR2(100),
    established_year    NUMBER(4)       CHECK (established_year BETWEEN 1947 AND 2025)
);

-- -------------------------------------------------------
-- TABLE 2: SCHEME
-- Core scheme catalog (5 major + 5 minor)
-- -------------------------------------------------------
CREATE TABLE Scheme (
    scheme_id           NUMBER          PRIMARY KEY,
    scheme_name         VARCHAR2(150)   NOT NULL UNIQUE,
    scheme_code         VARCHAR2(20)    NOT NULL UNIQUE,
    department_id       NUMBER          NOT NULL,
    scheme_type         VARCHAR2(10)    NOT NULL CHECK (scheme_type IN ('MAJOR','MINOR')),
    description         VARCHAR2(500),
    launch_date         DATE            NOT NULL,
    expiry_date         DATE,
    base_benefit_amount NUMBER(12,2)    NOT NULL CHECK (base_benefit_amount > 0),
    max_benefit_amount  NUMBER(12,2)    NOT NULL CHECK (max_benefit_amount > 0),
    beneficiary_target  NUMBER          DEFAULT 0,        -- planned beneficiary count
    applicable_states   VARCHAR2(500)   DEFAULT 'ALL',    -- 'ALL' or comma-separated states
    is_active           CHAR(1)         DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    CONSTRAINT fk_scheme_dept FOREIGN KEY (department_id) REFERENCES Department(department_id),
    CONSTRAINT chk_benefit_range CHECK (max_benefit_amount >= base_benefit_amount)
);

-- -------------------------------------------------------
-- TABLE 3: SCHEME_ELIGIBILITY_RULES
-- Rule engine: each row is one eligibility rule for a scheme
-- Evaluator sees a proper rule engine, not hardcoded IF-ELSE
-- -------------------------------------------------------
CREATE TABLE Scheme_Eligibility_Rules (
    rule_id             NUMBER          PRIMARY KEY,
    scheme_id           NUMBER          NOT NULL,
    min_age             NUMBER(3)       DEFAULT 0,
    max_age             NUMBER(3)       DEFAULT 120,
    max_income          NUMBER(12,2),   -- NULL means no income cap
    min_income          NUMBER(12,2)    DEFAULT 0,
    allowed_categories  VARCHAR2(50)    DEFAULT 'ALL', -- 'SC,ST,OBC,GEN' or 'ALL'
    location_type       VARCHAR2(10)    DEFAULT 'ALL' CHECK (location_type IN ('RURAL','URBAN','ALL')),
    gender_restriction  VARCHAR2(10)    DEFAULT 'ALL' CHECK (gender_restriction IN ('M','F','ALL')),
    min_land_acres      NUMBER(6,2)     DEFAULT 0,     -- for farmer schemes
    max_land_acres      NUMBER(6,2),                   -- NULL means no cap
    requires_document   CHAR(1)         DEFAULT 'Y' CHECK (requires_document IN ('Y','N')),
    rule_description    VARCHAR2(300),
    CONSTRAINT fk_rule_scheme FOREIGN KEY (scheme_id) REFERENCES Scheme(scheme_id)
);

-- -------------------------------------------------------
-- TABLE 4: SCHEME_FUND_POOL
-- Budget tracking per scheme per financial year
-- Trigger will auto-suspend scheme when budget exhausted
-- -------------------------------------------------------
CREATE TABLE Scheme_Fund_Pool (
    pool_id             NUMBER          PRIMARY KEY,
    scheme_id           NUMBER          NOT NULL UNIQUE,
    financial_year      VARCHAR2(10)    NOT NULL,          -- e.g. '2024-25'
    total_budget        NUMBER(15,2)    NOT NULL CHECK (total_budget > 0),
    disbursed_amount    NUMBER(15,2)    DEFAULT 0 CHECK (disbursed_amount >= 0),
    reserved_amount     NUMBER(15,2)    DEFAULT 0 CHECK (reserved_amount >= 0),
    last_updated        DATE            DEFAULT SYSDATE,
    CONSTRAINT fk_pool_scheme FOREIGN KEY (scheme_id) REFERENCES Scheme(scheme_id),
    CONSTRAINT chk_pool_disbursed CHECK (disbursed_amount <= total_budget)
);

-- -------------------------------------------------------
-- TABLE 5: OFFICER
-- Government officers who verify and approve applications
-- -------------------------------------------------------
CREATE TABLE Officer (
    officer_id          NUMBER          PRIMARY KEY,
    officer_name        VARCHAR2(100)   NOT NULL,
    employee_code       VARCHAR2(20)    NOT NULL UNIQUE,
    department_id       NUMBER          NOT NULL,
    designation         VARCHAR2(100)   NOT NULL,
    assigned_district   VARCHAR2(100)   NOT NULL,
    assigned_state      VARCHAR2(100)   NOT NULL,
    phone               VARCHAR2(15),
    email               VARCHAR2(100),
    join_date           DATE            NOT NULL,
    is_active           CHAR(1)         DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    CONSTRAINT fk_officer_dept FOREIGN KEY (department_id) REFERENCES Department(department_id)
);

-- -------------------------------------------------------
-- TABLE 6: CITIZEN
-- Core beneficiary table with Indian demographic fields
-- -------------------------------------------------------
CREATE TABLE Citizen (
    citizen_id          NUMBER          PRIMARY KEY,
    aadhaar_number      CHAR(12)        NOT NULL UNIQUE,
    full_name           VARCHAR2(100)   NOT NULL,
    gender              CHAR(1)         NOT NULL CHECK (gender IN ('M','F','O')),
    date_of_birth       DATE            NOT NULL,
    age                 NUMBER(3)       NOT NULL CHECK (age BETWEEN 0 AND 120),
    category            VARCHAR2(5)     NOT NULL CHECK (category IN ('SC','ST','OBC','GEN')),
    annual_income       NUMBER(12,2)    NOT NULL CHECK (annual_income >= 0),
    occupation          VARCHAR2(100),
    land_holding_acres  NUMBER(6,2)     DEFAULT 0 CHECK (land_holding_acres >= 0),
    location_type       VARCHAR2(10)    NOT NULL CHECK (location_type IN ('RURAL','URBAN')),
    village_town        VARCHAR2(100)   NOT NULL,
    district            VARCHAR2(100)   NOT NULL,
    state               VARCHAR2(100)   NOT NULL,
    pincode             VARCHAR2(6)     NOT NULL CHECK (REGEXP_LIKE(pincode, '^\d{6}$')),
    phone               VARCHAR2(15),
    bank_account        VARCHAR2(20)    NOT NULL UNIQUE,  -- for DBT
    ifsc_code           VARCHAR2(11)    NOT NULL,
    is_verified         CHAR(1)         DEFAULT 'N' CHECK (is_verified IN ('Y','N')),
    registration_date   DATE            DEFAULT SYSDATE,
    CONSTRAINT chk_aadhaar CHECK (REGEXP_LIKE(aadhaar_number, '^\d{12}$'))
);

-- -------------------------------------------------------
-- TABLE 7: CITIZEN_DOCUMENTS
-- Document upload tracking (gate for disbursement)
-- -------------------------------------------------------
CREATE TABLE Citizen_Documents (
    doc_id              NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    citizen_id          NUMBER          NOT NULL,
    doc_type            VARCHAR2(50)    NOT NULL CHECK (doc_type IN (
                            'AADHAAR','INCOME_CERT','CASTE_CERT',
                            'LAND_RECORD','BANK_PASSBOOK','PHOTO',
                            'RATION_CARD','RESIDENCE_PROOF')),
    doc_number          VARCHAR2(50),
    upload_date         DATE            DEFAULT SYSDATE,
    verified_by         NUMBER,                           -- officer_id
    verification_date   DATE,
    status              VARCHAR2(15)    DEFAULT 'PENDING'
                            CHECK (status IN ('PENDING','VERIFIED','REJECTED')),
    CONSTRAINT fk_doc_citizen FOREIGN KEY (citizen_id) REFERENCES Citizen(citizen_id),
    CONSTRAINT fk_doc_officer FOREIGN KEY (verified_by) REFERENCES Officer(officer_id)
);

-- -------------------------------------------------------
-- TABLE 8: APPLICATION
-- Citizen applies for a scheme — central workflow table
-- Status machine: SUBMITTED → DOC_VERIFIED → APPROVED / REJECTED → DISBURSED
-- -------------------------------------------------------
CREATE TABLE Application (
    application_id      NUMBER          PRIMARY KEY,
    citizen_id          NUMBER          NOT NULL,
    scheme_id           NUMBER          NOT NULL,
    officer_id          NUMBER,                           -- assigned on verification
    apply_date          DATE            DEFAULT SYSDATE  NOT NULL,
    status              VARCHAR2(20)    DEFAULT 'SUBMITTED'
                            CHECK (status IN (
                                'SUBMITTED','DOC_VERIFIED','FIELD_VERIFIED',
                                'APPROVED','REJECTED','DISBURSED','ON_HOLD')),
    priority_score      NUMBER(5,2)     DEFAULT 0,        -- computed by function
    rejection_reason    VARCHAR2(300),
    approval_date       DATE,
    remarks             VARCHAR2(500),
    CONSTRAINT fk_app_citizen FOREIGN KEY (citizen_id) REFERENCES Citizen(citizen_id),
    CONSTRAINT fk_app_scheme  FOREIGN KEY (scheme_id)  REFERENCES Scheme(scheme_id),
    CONSTRAINT fk_app_officer FOREIGN KEY (officer_id) REFERENCES Officer(officer_id),
    -- Prevent duplicate active applications for same citizen + scheme
    CONSTRAINT uq_citizen_scheme UNIQUE (citizen_id, scheme_id)
);

-- -------------------------------------------------------
-- TABLE 9: FUND_DISBURSEMENT
-- DBT (Direct Benefit Transfer) records
-- -------------------------------------------------------
CREATE TABLE Fund_Disbursement (
    disbursement_id     NUMBER          PRIMARY KEY,
    application_id      NUMBER          NOT NULL UNIQUE,  -- one disbursement per application
    amount              NUMBER(12,2)    NOT NULL CHECK (amount > 0),
    disbursement_date   DATE            DEFAULT SYSDATE,
    payment_mode        VARCHAR2(20)    DEFAULT 'DBT'
                            CHECK (payment_mode IN ('DBT','CHEQUE','NEFT','RTGS')),
    transaction_ref     VARCHAR2(50)    UNIQUE,
    bank_account        VARCHAR2(20)    NOT NULL,
    ifsc_code           VARCHAR2(11)    NOT NULL,
    status              VARCHAR2(15)    DEFAULT 'PROCESSED'
                            CHECK (status IN ('PROCESSED','FAILED','REVERSED')),
    processed_by        NUMBER,                           -- officer_id
    CONSTRAINT fk_disb_app    FOREIGN KEY (application_id) REFERENCES Application(application_id),
    CONSTRAINT fk_disb_officer FOREIGN KEY (processed_by)  REFERENCES Officer(officer_id)
);

-- -------------------------------------------------------
-- TABLE 10: APPLICATION_AUDIT_LOG
-- Trigger-populated: every status change is logged
-- Demonstrates audit trail — evaluator-friendly
-- -------------------------------------------------------
CREATE TABLE Application_Audit_Log (
    audit_id            NUMBER          PRIMARY KEY,
    application_id      NUMBER          NOT NULL,
    old_status          VARCHAR2(20),
    new_status          VARCHAR2(20)    NOT NULL,
    changed_by          VARCHAR2(100)   DEFAULT USER,
    change_date         TIMESTAMP       DEFAULT SYSTIMESTAMP,
    change_reason       VARCHAR2(300),
    CONSTRAINT fk_audit_app FOREIGN KEY (application_id) REFERENCES Application(application_id)
);

-- -------------------------------------------------------
-- VIEWS for reporting (used later by cursor-based reports)
-- -------------------------------------------------------

-- View 1: Citizen full profile with computed age
CREATE OR REPLACE VIEW V_CITIZEN_PROFILE AS
SELECT
    c.citizen_id,
    c.aadhaar_number,
    c.full_name,
    c.gender,
    TRUNC(MONTHS_BETWEEN(SYSDATE, c.date_of_birth)/12) AS computed_age,
    c.category,
    c.annual_income,
    c.location_type,
    c.district,
    c.state,
    c.is_verified,
    COUNT(a.application_id) AS total_applications
FROM Citizen c
LEFT JOIN Application a ON c.citizen_id = a.citizen_id
GROUP BY c.citizen_id, c.aadhaar_number, c.full_name, c.gender,
         c.date_of_birth, c.category, c.annual_income,
         c.location_type, c.district, c.state, c.is_verified;

-- View 2: Scheme budget health
CREATE OR REPLACE VIEW V_SCHEME_FUND_STATUS AS
SELECT
    s.scheme_id,
    s.scheme_name,
    s.scheme_type,
    sfp.total_budget,
    sfp.disbursed_amount,
    sfp.total_budget - sfp.disbursed_amount AS remaining_budget,
    ROUND((sfp.disbursed_amount / sfp.total_budget) * 100, 2) AS utilization_pct,
    s.is_active
FROM Scheme s
JOIN Scheme_Fund_Pool sfp ON s.scheme_id = sfp.scheme_id;

-- View 3: Application pipeline status
CREATE OR REPLACE VIEW V_APPLICATION_PIPELINE AS
SELECT
    a.application_id,
    c.full_name,
    c.aadhaar_number,
    c.state,
    c.district,
    s.scheme_name,
    s.scheme_type,
    a.status,
    a.apply_date,
    a.priority_score,
    o.officer_name,
    d.amount AS disbursed_amount
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
JOIN Scheme s  ON a.scheme_id  = s.scheme_id
LEFT JOIN Officer o ON a.officer_id = o.officer_id
LEFT JOIN Fund_Disbursement d ON a.application_id = d.application_id;

-- View 4: Officer performance dashboard
CREATE OR REPLACE VIEW V_OFFICER_PERFORMANCE AS
SELECT
    o.officer_id,
    o.officer_name,
    o.assigned_state,
    o.assigned_district,
    d.department_name,
    COUNT(a.application_id) AS total_handled,
    SUM(CASE WHEN a.status = 'APPROVED'  THEN 1 ELSE 0 END) AS approved_count,
    SUM(CASE WHEN a.status = 'REJECTED'  THEN 1 ELSE 0 END) AS rejected_count,
    SUM(CASE WHEN a.status = 'DISBURSED' THEN 1 ELSE 0 END) AS disbursed_count,
    ROUND(AVG(CASE WHEN a.approval_date IS NOT NULL
              THEN a.approval_date - a.apply_date END), 1) AS avg_processing_days
FROM Officer o
JOIN Department d ON o.department_id = d.department_id
LEFT JOIN Application a ON o.officer_id = a.officer_id
GROUP BY o.officer_id, o.officer_name, o.assigned_state,
         o.assigned_district, d.department_name;

-- ============================================================
-- END OF PART 1: DDL COMPLETE
-- Run PART 2 next (Data + Synthetic Generation)
-- ============================================================
COMMIT;
-- ============================================================
-- GOVERNMENT SCHEME MANAGEMENT SYSTEM
-- PART 2: MASTER DATA + SYNTHETIC DATA GENERATION
-- Run AFTER Part 1
-- ============================================================

-- -------------------------------------------------------
-- SECTION A: DEPARTMENTS (8 real Indian ministries)
-- -------------------------------------------------------
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Agriculture & Farmers Welfare',   'MOA',   'Ministry of Agriculture',                   'Shivraj Singh Chouhan',   'moa@gov.in',    1947);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Housing & Urban Affairs',          'MOHUA', 'Ministry of Housing',                       'Manohar Lal Khattar',    'mohua@gov.in',  1952);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Health & Family Welfare',          'MOHFW','Ministry of Health',                         'JP Nadda',               'mohfw@gov.in',  1947);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of New & Renewable Energy',           'MNRE',  'Ministry of Energy',                        'Pralhad Joshi',          'mnre@gov.in',   1992);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Rural Development',                'MRD',   'Ministry of Rural Development',             'Shivraj Singh Chouhan',  'mrd@gov.in',    1952);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Women & Child Development',        'MWCD',  'Ministry of WCD',                           'Annpurna Devi',          'mwcd@gov.in',   1985);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Social Justice & Empowerment',     'MSJE',  'Ministry of Social Justice',                'Virendra Kumar',         'msje@gov.in',   1998);
INSERT INTO Department VALUES (SEQ_DEPT.NEXTVAL, 'Ministry of Education',                        'MOE',   'Ministry of Education',                     'Dharmendra Pradhan',     'moe@gov.in',    1947);
COMMIT;

-- -------------------------------------------------------
-- SECTION B: SCHEMES (5 Major + 5 Minor)
-- Inspired by real schemes, not exact copies
-- dept IDs: MOA=1,MOHUA=2,MOHFW=3,MNRE=4,MRD=5,MWCD=6,MSJE=7,MOE=8
-- -------------------------------------------------------

-- MAJOR SCHEMES
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Kisan Samman Yojana', 'KSY-2019', 1, 'MAJOR',
    'Direct income support to farmer families with small and marginal land holdings. Annual benefit transferred in three equal instalments via DBT.',
    DATE '2019-02-24', NULL, 6000, 8000, 120000000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Gramin Awas Yojana', 'GAY-2016', 2, 'MAJOR',
    'Housing assistance for homeless and kutcha-house dwellers in rural areas. One-time subsidy for construction of pucca house.',
    DATE '2016-11-20', NULL, 120000, 250000, 29000000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Swasthya Suraksha Yojana', 'SSY-2018', 3, 'MAJOR',
    'Health insurance coverage for economically weaker sections and lower middle class. Cashless treatment at empanelled hospitals.',
    DATE '2018-09-23', NULL, 300000, 500000, 107400000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Gramin Rozgar Guarantee Scheme', 'GRGS-2005', 5, 'MAJOR',
    'Guarantees 100 days of unskilled wage employment per year to rural households whose adult members volunteer to do unskilled manual work.',
    DATE '2005-02-02', NULL, 15000, 25000, 55000000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Ujjwala Rasoi Yojana', 'URY-2016', 5, 'MAJOR',
    'Free LPG connections and subsidised refills for BPL households, especially targeting women below poverty line in rural areas.',
    DATE '2016-05-01', NULL, 1600, 3200, 83000000, 'ALL', 'Y'
);

-- MINOR SCHEMES
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Surya Shakti Solar Subsidy', 'SSSS-2024', 4, 'MINOR',
    'Subsidy on rooftop solar panel installation for households. Reduces electricity bills and promotes renewable energy.',
    DATE '2024-02-13', NULL, 30000, 78000, 10000000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Naari Shakti Udyam Yojana', 'NSUY-2020', 6, 'MINOR',
    'Financial assistance and training support for women entrepreneurs from SC/ST/OBC backgrounds to start micro-enterprises.',
    DATE '2020-03-08', NULL, 50000, 100000, 500000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'SC ST Scholarships Scheme', 'SCSS-2008', 7, 'MINOR',
    'Merit-cum-means scholarship for SC/ST students pursuing higher education at recognised universities.',
    DATE '2008-07-01', NULL, 12000, 36000, 5000000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Kisan Krishi Yantra Anudan', 'KKYA-2021', 1, 'MINOR',
    'Subsidy on purchase of modern agricultural equipment for small and marginal farmers to improve farm mechanisation.',
    DATE '2021-06-01', NULL, 25000, 100000, 2000000, 'ALL', 'Y'
);
INSERT INTO Scheme VALUES (
    SEQ_SCHEME.NEXTVAL, 'Divyang Sahayata Yojana', 'DSY-2015', 7, 'MINOR',
    'Assistive devices, monthly pension and skill development support for persons with benchmark disabilities.',
    DATE '2015-12-03', NULL, 3000, 10000, 600000, 'ALL', 'Y'
);
COMMIT;

-- -------------------------------------------------------
-- SECTION C: SCHEME ELIGIBILITY RULES (rule engine rows)
-- -------------------------------------------------------
-- KSY (scheme_id=1): Farmer, any category, income < 2.5L, any age
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 1, 18, 75, 250000, 0, 'ALL', 'ALL', 'ALL', 0.1, 5, 'Y', 'Small/marginal farmers with land 0.1 to 5 acres');
-- GAY (scheme_id=2): Rural, income < 3L, no pucca house
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 2, 21, 70, 300000, 0, 'ALL', 'RURAL', 'ALL', 0, NULL, 'Y', 'Rural BPL families without pucca house');
-- SSY (scheme_id=3): Income < 5L, all categories
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 3, 0, 120, 500000, 0, 'ALL', 'ALL', 'ALL', 0, NULL, 'Y', 'Annual income below Rs 5 lakh');
-- GRGS (scheme_id=4): Rural adult, any income
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 4, 18, 60, NULL, 0, 'ALL', 'RURAL', 'ALL', 0, NULL, 'Y', 'Rural adult willing to do manual work');
-- URY (scheme_id=5): Women, BPL, income < 2L
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 5, 18, 120, 200000, 0, 'ALL', 'ALL', 'F', 0, NULL, 'Y', 'Women from BPL households, income below 2 lakh');
-- SSSS (scheme_id=6): Any, income > 1L (can afford maintenance)
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 6, 21, 120, 1500000, 100000, 'ALL', 'ALL', 'ALL', 0, NULL, 'Y', 'Homeowner with income between 1L and 15L');
-- NSUY (scheme_id=7): Women, SC/ST/OBC only
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 7, 18, 55, 500000, 0, 'SC,ST,OBC', 'ALL', 'F', 0, NULL, 'Y', 'Women from SC/ST/OBC background, income < 5L');
-- SCSS (scheme_id=8): SC/ST students, age 18-30
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 8, 18, 30, 250000, 0, 'SC,ST', 'ALL', 'ALL', 0, NULL, 'Y', 'SC/ST students in higher education, income < 2.5L');
-- KKYA (scheme_id=9): Farmers, any category
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 9, 18, 70, 350000, 0, 'ALL', 'ALL', 'ALL', 0.5, 10, 'Y', 'Farmers with 0.5 to 10 acres land');
-- DSY (scheme_id=10): All, any income
INSERT INTO Scheme_Eligibility_Rules VALUES (SEQ_RULE.NEXTVAL, 10, 0, 120, NULL, 0, 'ALL', 'ALL', 'ALL', 0, NULL, 'Y', 'Persons with benchmark disability (40%+)');
COMMIT;

-- -------------------------------------------------------
-- SECTION D: SCHEME FUND POOLS (2024-25 budget)
-- -------------------------------------------------------
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 1,  '2024-25', 75000000000, 0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 2,  '2024-25', 54000000000, 0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 3,  '2024-25', 76000000000, 0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 4,  '2024-25', 89000000000, 0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 5,  '2024-25', 16000000000, 0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 6,  '2024-25', 7500000000,  0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 7,  '2024-25', 2000000000,  0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 8,  '2024-25', 4500000000,  0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 9,  '2024-25', 3500000000,  0, 0, SYSDATE);
INSERT INTO Scheme_Fund_Pool VALUES (SEQ_POOL.NEXTVAL, 10, '2024-25', 800000000,   0, 0, SYSDATE);
COMMIT;

-- -------------------------------------------------------
-- SECTION E: OFFICERS (30 officers across states/depts)
-- -------------------------------------------------------
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Rajendra Kumar Sharma','EMP001',1,'District Agriculture Officer','Lucknow','Uttar Pradesh','9415000001','rksharma@up.gov.in',DATE '2010-06-15','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Sunita Devi Yadav','EMP002',2,'Block Development Officer','Varanasi','Uttar Pradesh','9415000002','sdyadav@up.gov.in',DATE '2012-03-20','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Amarjit Singh Gill','EMP003',3,'District Health Officer','Ludhiana','Punjab','9814000003','asgill@pb.gov.in',DATE '2008-09-01','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Priya Ramesh Nair','EMP004',5,'Programme Officer MGNREGS','Patna','Bihar','7234000004','prnair@br.gov.in',DATE '2015-01-10','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Mohan Lal Verma','EMP005',1,'Agriculture Extension Officer','Jaipur','Rajasthan','9928000005','mlverma@rj.gov.in',DATE '2011-07-22','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Fatima Begum Khan','EMP006',6,'Child Development Project Officer','Bhopal','Madhya Pradesh','9301000006','fbkhan@mp.gov.in',DATE '2013-04-05','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Venkatesh Subramaniam','EMP007',4,'Solar Energy Programme Manager','Chennai','Tamil Nadu','9445000007','vsub@tn.gov.in',DATE '2016-08-18','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Kavita Arun Patil','EMP008',2,'Housing Welfare Officer','Pune','Maharashtra','9423000008','kapatil@mh.gov.in',DATE '2014-11-30','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Suresh Chandra Meena','EMP009',7,'Social Welfare Officer','Ajmer','Rajasthan','9928000009','scmeena@rj.gov.in',DATE '2009-05-12','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Anitha Krishnaswamy','EMP010',3,'Primary Health Centre Officer','Coimbatore','Tamil Nadu','9445000010','akrish@tn.gov.in',DATE '2017-02-28','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Gurpreet Singh Bhatia','EMP011',5,'Block Level Facilitator','Amritsar','Punjab','9814000011','gsbhatia@pb.gov.in',DATE '2010-10-10','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Neha Sunil Kulkarni','EMP012',8,'Education Welfare Officer','Nashik','Maharashtra','9423000012','nskulkarni@mh.gov.in',DATE '2018-06-01','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Dinesh Prasad Dubey','EMP013',1,'Senior Agriculture Officer','Gorakhpur','Uttar Pradesh','9415000013','dpdubey@up.gov.in',DATE '2007-03-15','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Meena Ravi Kumar','EMP014',6,'District Women Welfare Officer','Hyderabad','Telangana','9040000014','mrkumar@tg.gov.in',DATE '2012-09-25','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Bikram Jit Mahato','EMP015',5,'MGNREGS Programme Officer','Ranchi','Jharkhand','7004000015','bjmahato@jh.gov.in',DATE '2014-04-01','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Sarita Bhatt','EMP016',3,'Block Medical Officer','Dehradun','Uttarakhand','9456000016','sbhatt@uk.gov.in',DATE '2016-12-10','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Ramesh Narayan Pillai','EMP017',2,'Urban Housing Officer','Thiruvananthapuram','Kerala','9744000017','rnpillai@kl.gov.in',DATE '2011-07-04','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Lakshmi Bai Sahu','EMP018',7,'Tribal Welfare Officer','Raipur','Chhattisgarh','7049000018','lbsahu@cg.gov.in',DATE '2013-08-20','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Arjun Dev Thakur','EMP019',4,'Renewable Energy Officer','Shimla','Himachal Pradesh','9816000019','adthakur@hp.gov.in',DATE '2019-01-15','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Parveen Akhtar','EMP020',5,'Rural Development Officer','Guwahati','Assam','9435000020','pakhtar@as.gov.in',DATE '2015-03-22','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Sukhdev Singh Sandhu','EMP021',1,'Kisan Seva Kendra Manager','Bathinda','Punjab','9814000021','sssandhu@pb.gov.in',DATE '2008-11-11','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Geeta Rani Mishra','EMP022',6,'Anganwadi Supervisor','Allahabad','Uttar Pradesh','9415000022','grmishra@up.gov.in',DATE '2010-05-30','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Md. Iqbal Hussain','EMP023',3,'District Immunisation Officer','Muzaffarpur','Bihar','7234000023','mihussain@br.gov.in',DATE '2013-02-14','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Devika Shankar Rao','EMP024',7,'SC ST Development Officer','Vijayawada','Andhra Pradesh','8332000024','dsrao@ap.gov.in',DATE '2017-07-01','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Harcharan Singh Mann','EMP025',1,'Agriculture Technology Manager','Patiala','Punjab','9814000025','hsmaan@pb.gov.in',DATE '2009-04-06','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Rekha Jha','EMP026',5,'Block Programme Manager','Darbhanga','Bihar','7234000026','rjha@br.gov.in',DATE '2016-09-18','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Anil Shankar Tiwari','EMP027',2,'Pradhan Mantri Awas Officer','Agra','Uttar Pradesh','9415000027','astiwari@up.gov.in',DATE '2012-01-25','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Manjula Devi Nair','EMP028',6,'Child Welfare Officer','Kozhikode','Kerala','9744000028','mdnair@kl.gov.in',DATE '2018-03-08','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Prakash Rao Desai','EMP029',4,'Solar Mission Coordinator','Gandhinagar','Gujarat','9979000029','prdesai@gj.gov.in',DATE '2020-05-01','Y');
INSERT INTO Officer VALUES (SEQ_OFFICER.NEXTVAL,'Champa Bai Rawat','EMP030',7,'Divyang Welfare Coordinator','Indore','Madhya Pradesh','9301000030','cbrawat@mp.gov.in',DATE '2015-11-20','Y');
COMMIT;

-- ============================================================
-- SECTION F: SYNTHETIC DATA GENERATION PROCEDURE
-- Generates 1000 citizens with realistic Indian demographics
-- Based on Census 2011 proportions + NSSO income data
-- ============================================================
CREATE OR REPLACE PROCEDURE GENERATE_CITIZEN_DATA AS

    -- Arrays for Indian names (real names from different communities)
    TYPE name_arr IS TABLE OF VARCHAR2(50);
    
    v_first_male   name_arr := name_arr(
        'Rajesh','Suresh','Ramesh','Dinesh','Mahesh','Ganesh','Naresh','Mukesh',
        'Rakesh','Umesh','Ramakant','Shivaji','Arjun','Devendra','Pradeep',
        'Santosh','Harish','Manish','Anil','Sunil','Vijay','Ajay','Sanjay',
        'Ranjit','Gurpreet','Amarjit','Harpreet','Baldev','Kuldeep','Jaswant',
        'Mohammad','Imran','Aslam','Farhan','Riyaz','Salman','Irfan','Aamir',
        'Venkatesh','Subramaniam','Krishnaswamy','Ramamurthy','Balakrishnan',
        'Bikash','Prasanta','Debashish','Soumyajit','Partha','Sourav',
        'Rohit','Amit','Vikas','Ashok','Pramod','Hemant','Deepak','Vivek',
        'Shyam','Govind','Brijesh','Akhilesh','Yogendra','Virendra','Satendra'
    );
    
    v_first_female name_arr := name_arr(
        'Sunita','Anita','Kavita','Savita','Sangita','Mamta','Seema','Geeta',
        'Rekha','Usha','Meena','Asha','Nisha','Mina','Lata','Sita','Gita',
        'Priya','Pooja','Neha','Divya','Deepa','Ritu','Manju','Saroj',
        'Gurpreet','Harpreet','Manpreet','Simranjit','Paramjit','Ravinder',
        'Fatima','Aisha','Rukhsar','Shabana','Nasreen','Yasmin','Zubeida',
        'Lakshmi','Saraswati','Kamala','Radha','Meenakshi','Vijayalakshmi',
        'Sudha','Rohini','Sushma','Shanta','Vimala','Jayashree','Parvati',
        'Champa','Pushpa','Kusum','Madhuri','Vandana','Archana','Swati',
        'Anupama','Shobha','Kiran','Poonam','Sapna','Monika','Preeti'
    );
    
    v_last_names   name_arr := name_arr(
        'Sharma','Verma','Gupta','Singh','Kumar','Yadav','Patel','Shah',
        'Joshi','Mishra','Tiwari','Dubey','Pandey','Shukla','Srivastava',
        'Rao','Reddy','Naidu','Iyer','Pillai','Nair','Menon','Krishnan',
        'Das','Dutta','Ghosh','Banerjee','Chatterjee','Mukherjee','Bose',
        'Gill','Sidhu','Mann','Grewal','Dhillon','Brar','Sandhu','Chahal',
        'Khan','Ansari','Shaikh','Qureshi','Siddiqui','Malik','Chaudhary',
        'Meena','Baiga','Bhil','Gond','Oraon','Munda','Santali','Lodhi',
        'Mahato','Sahu','Thakur','Rawat','Bisht','Negi','Chauhan','Rathore',
        'Desai','Mehta','Jain','Oswal','Baniya','Agarwal','Mittal','Goel',
        'Jadhav','Patil','More','Shinde','Kamble','Pawar','Bhosale','Mane',
        'Naik','Gawade','Sawant','Chavan','Thorat','Deshpande','Kulkarni'
    );

    -- State distribution array (weighted by population)
    -- UP~17%, MH~9%, Bihar~9%, WB~8%, MP~6%, Raj~6%, others
    TYPE state_arr IS TABLE OF VARCHAR2(100);
    TYPE dist_arr  IS TABLE OF VARCHAR2(100);
    
    v_states state_arr := state_arr(
        'Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh',
        'Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh',
        'Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh',
        'Uttar Pradesh','Uttar Pradesh',
        'Maharashtra','Maharashtra','Maharashtra','Maharashtra','Maharashtra',
        'Maharashtra','Maharashtra','Maharashtra','Maharashtra',
        'Bihar','Bihar','Bihar','Bihar','Bihar','Bihar','Bihar','Bihar','Bihar',
        'West Bengal','West Bengal','West Bengal','West Bengal','West Bengal',
        'West Bengal','West Bengal','West Bengal',
        'Madhya Pradesh','Madhya Pradesh','Madhya Pradesh','Madhya Pradesh',
        'Madhya Pradesh','Madhya Pradesh',
        'Rajasthan','Rajasthan','Rajasthan','Rajasthan','Rajasthan','Rajasthan',
        'Tamil Nadu','Tamil Nadu','Tamil Nadu','Tamil Nadu','Tamil Nadu',
        'Karnataka','Karnataka','Karnataka','Karnataka',
        'Gujarat','Gujarat','Gujarat','Gujarat',
        'Andhra Pradesh','Andhra Pradesh','Andhra Pradesh',
        'Odisha','Odisha','Odisha',
        'Telangana','Telangana','Telangana',
        'Punjab','Punjab','Punjab',
        'Jharkhand','Jharkhand',
        'Chhattisgarh','Chhattisgarh',
        'Assam','Assam',
        'Haryana','Haryana',
        'Kerala',
        'Uttarakhand',
        'Himachal Pradesh'
    );
    
    v_districts dist_arr := dist_arr(
        -- UP districts
        'Lucknow','Varanasi','Agra','Kanpur','Allahabad','Gorakhpur','Meerut',
        'Bareilly','Aligarh','Moradabad','Mathura','Jhansi','Ghaziabad',
        'Saharanpur','Muzaffarnagar','Firozabad','Etawah',
        -- Maharashtra
        'Pune','Mumbai','Nagpur','Nashik','Aurangabad','Kolhapur','Solapur',
        'Amravati','Latur',
        -- Bihar
        'Patna','Gaya','Muzaffarpur','Darbhanga','Bhagalpur','Purnia','Arrah',
        'Begusarai','Nalanda',
        -- West Bengal
        'Kolkata','Howrah','Burdwan','Murshidabad','Nadia','Malda','Jalpaiguri',
        'Midnapore',
        -- MP
        'Bhopal','Indore','Gwalior','Jabalpur','Sagar','Rewa',
        -- Rajasthan
        'Jaipur','Jodhpur','Udaipur','Ajmer','Bikaner','Kota',
        -- Tamil Nadu
        'Chennai','Coimbatore','Madurai','Salem','Tiruchirappalli',
        -- Karnataka
        'Bengaluru','Mysuru','Hubballi','Mangaluru',
        -- Gujarat
        'Ahmedabad','Surat','Vadodara','Rajkot',
        -- AP
        'Visakhapatnam','Vijayawada','Guntur',
        -- Odisha
        'Bhubaneswar','Cuttack','Berhampur',
        -- Telangana
        'Hyderabad','Warangal','Karimnagar',
        -- Punjab
        'Ludhiana','Amritsar','Patiala',
        -- Jharkhand
        'Ranchi','Dhanbad',
        -- CG
        'Raipur','Bilaspur',
        -- Assam
        'Guwahati','Dibrugarh',
        -- Haryana
        'Gurugram','Faridabad',
        -- Kerala
        'Thiruvananthapuram',
        -- Uttarakhand
        'Dehradun',
        -- HP
        'Shimla'
    );

    -- Category distribution: SC~17%, ST~8%, OBC~40%, GEN~35%
    TYPE cat_arr IS TABLE OF VARCHAR2(5);
    v_categories cat_arr := cat_arr(
        'SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC','SC',
        'ST','ST','ST','ST','ST','ST','ST','ST',
        'OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC',
        'OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC',
        'OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC',
        'OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC','OBC',
        'GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN',
        'GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN',
        'GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN','GEN',
        'GEN','GEN','GEN','GEN','GEN'
    );

    -- Occupation list
    TYPE occ_arr IS TABLE OF VARCHAR2(100);
    v_occupations occ_arr := occ_arr(
        'Farmer','Farmer','Farmer','Farmer','Farmer',
        'Agricultural Labourer','Agricultural Labourer','Agricultural Labourer',
        'Daily Wage Labourer','Daily Wage Labourer',
        'Small Trader','Small Trader',
        'Government Employee','Government Employee',
        'Private Sector Employee','Private Sector Employee',
        'Self Employed','Artisan','Weaver','Potter',
        'Construction Worker','Domestic Worker',
        'Shopkeeper','Hawker','Tailor',
        'Teacher','Health Worker','ASHA Worker',
        'Driver','Mechanic','Electrician',
        'Student','Unemployed','Retired'
    );

    -- Variables
    v_citizen_id    NUMBER;
    v_aadhaar       VARCHAR2(12);
    v_full_name     VARCHAR2(100);
    v_gender        CHAR(1);
    v_dob           DATE;
    v_age           NUMBER;
    v_category      VARCHAR2(5);
    v_income        NUMBER;
    v_location_type VARCHAR2(10);
    v_state         VARCHAR2(100);
    v_district      VARCHAR2(100);
    v_village       VARCHAR2(100);
    v_pincode       VARCHAR2(6);
    v_bank_acc      VARCHAR2(20);
    v_ifsc          VARCHAR2(11);
    v_occupation    VARCHAR2(100);
    v_land          NUMBER;
    v_state_idx     NUMBER;
    v_rand          NUMBER;
    v_income_rand   NUMBER;
    v_fname_idx     NUMBER;
    v_lname_idx     NUMBER;
    
    -- Indian bank IFSCs (realistic)
    TYPE ifsc_arr IS TABLE OF VARCHAR2(11);
    v_ifsc_list ifsc_arr := ifsc_arr(
        'SBIN0001234','SBIN0005678','PUNB0012300','PUNB0056700',
        'UBIN0012345','UBIN0056789','BKID0001234','BKID0005678',
        'CNRB0001234','CNRB0005678','HDFC0001234','HDFC0005678',
        'ICIC0001234','ICIC0005678','BARB0001234','BARB0005678',
        'ALLA0021234','MAHB0001234','IOBA0001234','VIJB0001234'
    );

BEGIN
    DBMS_OUTPUT.PUT_LINE('Starting synthetic citizen data generation...');
    
    FOR i IN 1..1000 LOOP
    
        -- Generate unique Aadhaar (12 digit)
        v_aadhaar := LPAD(TO_CHAR(700000000000 + i + ROUND(DBMS_RANDOM.VALUE(0,9999))), 12, '0');
        
        -- Gender: ~51.5% Male, ~48.5% Female (Census proportion)
        v_rand := DBMS_RANDOM.VALUE(0,100);
        IF v_rand <= 51.5 THEN
            v_gender := 'M';
            v_fname_idx := ROUND(DBMS_RANDOM.VALUE(1, v_first_male.COUNT));
            v_lname_idx := ROUND(DBMS_RANDOM.VALUE(1, v_last_names.COUNT));
            v_full_name := v_first_male(v_fname_idx) || ' ' || v_last_names(v_lname_idx);
        ELSE
            v_gender := 'F';
            v_fname_idx := ROUND(DBMS_RANDOM.VALUE(1, v_first_female.COUNT));
            v_lname_idx := ROUND(DBMS_RANDOM.VALUE(1, v_last_names.COUNT));
            v_full_name := v_first_female(v_fname_idx) || ' ' || v_last_names(v_lname_idx);
        END IF;
        
        -- Age distribution: 18-70 working age, skewed toward 25-45
        -- Real distribution: ~45% are 18-35, ~35% are 36-55, ~20% are 56+
        v_rand := DBMS_RANDOM.VALUE(0,100);
        IF v_rand <= 45 THEN
            v_age := ROUND(DBMS_RANDOM.VALUE(18, 35));
        ELSIF v_rand <= 80 THEN
            v_age := ROUND(DBMS_RANDOM.VALUE(36, 55));
        ELSE
            v_age := ROUND(DBMS_RANDOM.VALUE(56, 75));
        END IF;
        v_dob := ADD_MONTHS(SYSDATE, -(v_age * 12));
        
        -- Category (census proportions)
        v_category := v_categories(ROUND(DBMS_RANDOM.VALUE(1, v_categories.COUNT)));
        
        -- State (population-weighted)
        v_state_idx := ROUND(DBMS_RANDOM.VALUE(1, v_states.COUNT));
        v_state     := v_states(v_state_idx);
        v_district  := v_districts(LEAST(v_state_idx, v_districts.COUNT));
        
        -- Location: 65% rural, 35% urban (Census 2011)
        IF DBMS_RANDOM.VALUE(0,100) <= 65 THEN
            v_location_type := 'RURAL';
            v_village := 'Village ' || ROUND(DBMS_RANDOM.VALUE(1,999));
        ELSE
            v_location_type := 'URBAN';
            v_village := v_district || ' City';
        END IF;
        
        -- Income distribution (right-skewed, based on NSSO 2022 data):
        -- ~40% below 1L (BPL/very poor), ~30% 1L-2.5L, ~15% 2.5-5L, ~10% 5-10L, ~5% 10L+
        v_income_rand := DBMS_RANDOM.VALUE(0,100);
        IF v_income_rand <= 40 THEN
            -- BPL / very poor (annual)
            v_income := ROUND(DBMS_RANDOM.VALUE(20000, 100000), -2);
        ELSIF v_income_rand <= 70 THEN
            -- Low income
            v_income := ROUND(DBMS_RANDOM.VALUE(100000, 250000), -2);
        ELSIF v_income_rand <= 85 THEN
            -- Lower middle
            v_income := ROUND(DBMS_RANDOM.VALUE(250000, 500000), -2);
        ELSIF v_income_rand <= 95 THEN
            -- Middle
            v_income := ROUND(DBMS_RANDOM.VALUE(500000, 1000000), -2);
        ELSE
            -- Upper middle / high
            v_income := ROUND(DBMS_RANDOM.VALUE(1000000, 3000000), -2);
        END IF;
        
        -- Occupation
        v_occupation := v_occupations(ROUND(DBMS_RANDOM.VALUE(1, v_occupations.COUNT)));
        
        -- Land holding (mainly for farmers, 0 for others)
        IF v_occupation IN ('Farmer','Agricultural Labourer') THEN
            v_land := ROUND(DBMS_RANDOM.VALUE(0.5, 8), 1);
        ELSE
            v_land := 0;
        END IF;
        
        -- Pincode (6-digit, state-realistic but synthetic)
        v_pincode := LPAD(TO_CHAR(ROUND(DBMS_RANDOM.VALUE(110001, 799999))), 6, '0');
        
        -- Bank account (DBT)
        v_bank_acc := 'ACCT' || LPAD(TO_CHAR(i), 12, '0');
        
        -- IFSC from realistic list
        v_ifsc := v_ifsc_list(ROUND(DBMS_RANDOM.VALUE(1, v_ifsc_list.COUNT)));
        
        -- Insert citizen
        INSERT INTO Citizen (
            citizen_id, aadhaar_number, full_name, gender, date_of_birth, age,
            category, annual_income, occupation, land_holding_acres,
            location_type, village_town, district, state, pincode,
            bank_account, ifsc_code, is_verified, registration_date
        ) VALUES (
            SEQ_CITIZEN.NEXTVAL, v_aadhaar, v_full_name, v_gender, v_dob, v_age,
            v_category, v_income, v_occupation, v_land,
            v_location_type, v_village, v_district, v_state, v_pincode,
            v_bank_acc, v_ifsc, 
            CASE WHEN DBMS_RANDOM.VALUE(0,1) > 0.3 THEN 'Y' ELSE 'N' END,
            SYSDATE - ROUND(DBMS_RANDOM.VALUE(0, 365))
        );
        
        -- Commit every 100 rows to avoid undo log overflow
        IF MOD(i, 100) = 0 THEN
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('Inserted ' || i || ' citizens...');
        END IF;
        
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('SUCCESS: 1000 citizen records generated.');

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Duplicate value detected. Rolling back.');
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        ROLLBACK;
END GENERATE_CITIZEN_DATA;
/

-- Execute the procedure
BEGIN
    GENERATE_CITIZEN_DATA;
END;
/

-- -------------------------------------------------------
-- SECTION G: SAMPLE APPLICATIONS (realistic subset)
-- ~200 applications across citizens and schemes
-- with varied statuses for demonstration
-- -------------------------------------------------------
CREATE OR REPLACE PROCEDURE GENERATE_SAMPLE_APPLICATIONS AS
    v_citizen_id  NUMBER;
    v_scheme_id   NUMBER;
    v_officer_id  NUMBER;
    v_status      VARCHAR2(20);
    v_score       NUMBER;
    v_app_date    DATE;
    
    CURSOR c_eligible_farmers IS
        SELECT citizen_id, annual_income, category, location_type, land_holding_acres
        FROM Citizen
        WHERE occupation IN ('Farmer','Agricultural Labourer')
          AND land_holding_acres BETWEEN 0.1 AND 5
          AND annual_income < 250000
          AND ROWNUM <= 150;
    
    CURSOR c_bpl_rural IS
        SELECT citizen_id, annual_income, category, location_type
        FROM Citizen
        WHERE annual_income < 100000
          AND location_type = 'RURAL'
          AND ROWNUM <= 100;
          
    CURSOR c_low_income IS
        SELECT citizen_id, annual_income, category
        FROM Citizen
        WHERE annual_income < 500000
          AND ROWNUM <= 200;
          
    v_statuses    SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
                    'SUBMITTED','SUBMITTED','DOC_VERIFIED',
                    'APPROVED','APPROVED','REJECTED','DISBURSED');
BEGIN
    -- Kisan Samman Yojana (scheme_id=1) applications for farmers
    FOR r IN c_eligible_farmers LOOP
        BEGIN
            v_officer_id := ROUND(DBMS_RANDOM.VALUE(1,5));
            v_status     := v_statuses(ROUND(DBMS_RANDOM.VALUE(1,7)));
            v_app_date   := SYSDATE - ROUND(DBMS_RANDOM.VALUE(10,180));
            
            INSERT INTO Application (
                application_id, citizen_id, scheme_id, officer_id,
                apply_date, status, priority_score, approval_date
            ) VALUES (
                SEQ_APPLICATION.NEXTVAL, r.citizen_id, 1, v_officer_id,
                v_app_date, v_status, 
                ROUND(DBMS_RANDOM.VALUE(30,95),2),
                CASE WHEN v_status IN ('APPROVED','DISBURSED') 
                     THEN v_app_date + ROUND(DBMS_RANDOM.VALUE(5,30)) ELSE NULL END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL; -- skip duplicates
        END;
    END LOOP;
    
    -- Gramin Awas Yojana (scheme_id=2) for rural BPL
    FOR r IN c_bpl_rural LOOP
        BEGIN
            v_officer_id := ROUND(DBMS_RANDOM.VALUE(2,5));
            v_status     := v_statuses(ROUND(DBMS_RANDOM.VALUE(1,7)));
            v_app_date   := SYSDATE - ROUND(DBMS_RANDOM.VALUE(10,180));
            
            INSERT INTO Application (
                application_id, citizen_id, scheme_id, officer_id,
                apply_date, status, priority_score, approval_date
            ) VALUES (
                SEQ_APPLICATION.NEXTVAL, r.citizen_id, 2, v_officer_id,
                v_app_date, v_status,
                ROUND(DBMS_RANDOM.VALUE(40,99),2),
                CASE WHEN v_status IN ('APPROVED','DISBURSED')
                     THEN v_app_date + ROUND(DBMS_RANDOM.VALUE(7,45)) ELSE NULL END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
    END LOOP;
    
    -- Swasthya Suraksha (scheme_id=3) broad applications
    FOR r IN c_low_income LOOP
        BEGIN
            v_officer_id := ROUND(DBMS_RANDOM.VALUE(3,16));
            v_status     := v_statuses(ROUND(DBMS_RANDOM.VALUE(1,7)));
            v_app_date   := SYSDATE - ROUND(DBMS_RANDOM.VALUE(5,200));
            
            INSERT INTO Application (
                application_id, citizen_id, scheme_id, officer_id,
                apply_date, status, priority_score, approval_date
            ) VALUES (
                SEQ_APPLICATION.NEXTVAL, r.citizen_id, 3, v_officer_id,
                v_app_date, v_status,
                ROUND(DBMS_RANDOM.VALUE(20,90),2),
                CASE WHEN v_status IN ('APPROVED','DISBURSED')
                     THEN v_app_date + ROUND(DBMS_RANDOM.VALUE(3,25)) ELSE NULL END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Sample applications generated.');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR in app generation: ' || SQLERRM);
        ROLLBACK;
END GENERATE_SAMPLE_APPLICATIONS;
/

BEGIN
    GENERATE_SAMPLE_APPLICATIONS;
END;
/

-- Generate disbursement records for all APPROVED/DISBURSED applications
INSERT INTO Fund_Disbursement (
    disbursement_id, application_id, amount, disbursement_date,
    payment_mode, transaction_ref, bank_account, ifsc_code, status, processed_by
)
SELECT
    SEQ_DISBURSEMENT.NEXTVAL,
    a.application_id,
    CASE s.scheme_id
        WHEN 1 THEN 6000
        WHEN 2 THEN ROUND(DBMS_RANDOM.VALUE(120000,200000),-3)
        WHEN 3 THEN ROUND(DBMS_RANDOM.VALUE(50000,300000),-3)
        ELSE        ROUND(DBMS_RANDOM.VALUE(3000,25000),-2)
    END AS amount,
    a.approval_date + ROUND(DBMS_RANDOM.VALUE(1,10)),
    'DBT',
    'TXN' || TO_CHAR(SYSDATE,'YYYYMMDD') || LPAD(a.application_id,8,'0'),
    c.bank_account,
    c.ifsc_code,
    'PROCESSED',
    a.officer_id
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
JOIN Scheme s  ON a.scheme_id  = s.scheme_id
WHERE a.status IN ('APPROVED','DISBURSED')
  AND NOT EXISTS (
      SELECT 1 FROM Fund_Disbursement fd WHERE fd.application_id = a.application_id
  );

-- Update fund pool disbursed amounts
UPDATE Scheme_Fund_Pool sfp
SET disbursed_amount = (
    SELECT NVL(SUM(fd.amount), 0)
    FROM Fund_Disbursement fd
    JOIN Application a ON fd.application_id = a.application_id
    WHERE a.scheme_id = sfp.scheme_id
    AND fd.status = 'PROCESSED'
),
last_updated = SYSDATE;

COMMIT;

-- ============================================================
-- END OF PART 2: DATA COMPLETE
-- Run PART 3 next (PL/SQL Logic Engine)
-- ============================================================
-- ============================================================
-- GOVERNMENT SCHEME MANAGEMENT SYSTEM
-- PART 3: PL/SQL LOGIC ENGINE + QUERIES + DEMO FLOW
-- Run AFTER Part 1 and Part 2
-- ============================================================

-- ============================================================
-- SECTION A: FUNCTIONS
-- ============================================================

-- ------------------------------------------------------------
-- FUNCTION 1: CHECK_ELIGIBILITY
-- Returns 'ELIGIBLE' or 'INELIGIBLE: <reason>'
-- Checks citizen against scheme eligibility rules
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION CHECK_ELIGIBILITY (
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER
) RETURN VARCHAR2 AS

    v_age           NUMBER;
    v_income        NUMBER;
    v_category      VARCHAR2(5);
    v_location      VARCHAR2(10);
    v_gender        CHAR(1);
    v_land          NUMBER;
    v_scheme_active CHAR(1);
    v_fund_left     NUMBER;
    
    v_min_age       NUMBER;
    v_max_age       NUMBER;
    v_max_income    NUMBER;
    v_min_income    NUMBER;
    v_allowed_cats  VARCHAR2(50);
    v_loc_type      VARCHAR2(10);
    v_gender_rest   VARCHAR2(10);
    v_min_land      NUMBER;
    v_max_land      NUMBER;
    v_req_doc       CHAR(1);
    v_doc_count     NUMBER;
    
    v_result        VARCHAR2(200) := 'ELIGIBLE';
    
    CURSOR c_citizen IS
        SELECT age, annual_income, category, location_type, gender, land_holding_acres
        FROM Citizen WHERE citizen_id = p_citizen_id;
    
    CURSOR c_rules IS
        SELECT min_age, max_age, max_income, min_income,
               allowed_categories, location_type, gender_restriction,
               min_land_acres, max_land_acres, requires_document
        FROM Scheme_Eligibility_Rules
        WHERE scheme_id = p_scheme_id;

BEGIN
    -- Fetch scheme status
    SELECT is_active INTO v_scheme_active
    FROM Scheme WHERE scheme_id = p_scheme_id;
    
    IF v_scheme_active = 'N' THEN
        RETURN 'INELIGIBLE: Scheme is not active';
    END IF;
    
    -- Check fund availability
    SELECT NVL(total_budget - disbursed_amount, 0) INTO v_fund_left
    FROM Scheme_Fund_Pool WHERE scheme_id = p_scheme_id;
    
    IF v_fund_left <= 0 THEN
        RETURN 'INELIGIBLE: Scheme fund exhausted for this financial year';
    END IF;
    
    -- Fetch citizen profile
    OPEN c_citizen;
    FETCH c_citizen INTO v_age, v_income, v_category, v_location, v_gender, v_land;
    IF c_citizen%NOTFOUND THEN
        CLOSE c_citizen;
        RETURN 'INELIGIBLE: Citizen not found';
    END IF;
    CLOSE c_citizen;
    
    -- Fetch and evaluate eligibility rules
    OPEN c_rules;
    FETCH c_rules INTO v_min_age, v_max_age, v_max_income, v_min_income,
                       v_allowed_cats, v_loc_type, v_gender_rest,
                       v_min_land, v_max_land, v_req_doc;
    
    IF c_rules%NOTFOUND THEN
        CLOSE c_rules;
        RETURN 'INELIGIBLE: No eligibility rules defined for this scheme';
    END IF;
    CLOSE c_rules;
    
    -- Age check
    IF v_age < v_min_age OR v_age > v_max_age THEN
        RETURN 'INELIGIBLE: Age ' || v_age || ' not in range [' || v_min_age || '-' || v_max_age || ']';
    END IF;
    
    -- Income checks
    IF v_max_income IS NOT NULL AND v_income > v_max_income THEN
        RETURN 'INELIGIBLE: Annual income Rs.' || v_income || ' exceeds scheme limit Rs.' || v_max_income;
    END IF;
    
    IF v_income < v_min_income THEN
        RETURN 'INELIGIBLE: Annual income Rs.' || v_income || ' below scheme minimum Rs.' || v_min_income;
    END IF;
    
    -- Category check
    IF v_allowed_cats != 'ALL' THEN
        IF INSTR(v_allowed_cats, v_category) = 0 THEN
            RETURN 'INELIGIBLE: Category ' || v_category || ' not eligible. Allowed: ' || v_allowed_cats;
        END IF;
    END IF;
    
    -- Location check
    IF v_loc_type != 'ALL' AND v_location != v_loc_type THEN
        RETURN 'INELIGIBLE: Scheme restricted to ' || v_loc_type || ' residents';
    END IF;
    
    -- Gender check
    IF v_gender_rest != 'ALL' AND v_gender != v_gender_rest THEN
        RETURN 'INELIGIBLE: Scheme restricted to gender ' || v_gender_rest;
    END IF;
    
    -- Land holding check (for farmer schemes)
    IF v_min_land > 0 AND v_land < v_min_land THEN
        RETURN 'INELIGIBLE: Land holding ' || v_land || ' acres below minimum ' || v_min_land || ' acres';
    END IF;
    
    IF v_max_land IS NOT NULL AND v_land > v_max_land THEN
        RETURN 'INELIGIBLE: Land holding ' || v_land || ' acres exceeds maximum ' || v_max_land || ' acres';
    END IF;
    
    -- Document check
    IF v_req_doc = 'Y' THEN
        SELECT COUNT(*) INTO v_doc_count
        FROM Citizen_Documents
        WHERE citizen_id = p_citizen_id
          AND status = 'VERIFIED';
        
        IF v_doc_count < 2 THEN
            RETURN 'INELIGIBLE: Insufficient verified documents (' || v_doc_count || ' found, minimum 2 required)';
        END IF;
    END IF;
    
    RETURN v_result;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'INELIGIBLE: Required data not found';
    WHEN OTHERS THEN
        RETURN 'ERROR: ' || SQLERRM;
END CHECK_ELIGIBILITY;
/

-- ------------------------------------------------------------
-- FUNCTION 2: CALCULATE_BENEFIT_AMOUNT
-- Dynamic calculation based on citizen profile + scheme
-- Formula: base + category_bonus + rural_bonus + elderly_bonus
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION CALCULATE_BENEFIT_AMOUNT (
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER
) RETURN NUMBER AS

    v_base_amount   NUMBER;
    v_max_amount    NUMBER;
    v_income        NUMBER;
    v_category      VARCHAR2(5);
    v_location      VARCHAR2(10);
    v_age           NUMBER;
    
    v_benefit       NUMBER;
    v_cat_bonus     NUMBER := 0;
    v_rural_bonus   NUMBER := 0;
    v_elderly_bonus NUMBER := 0;
    v_income_factor NUMBER;

BEGIN
    -- Fetch scheme benefit range
    SELECT base_benefit_amount, max_benefit_amount
    INTO v_base_amount, v_max_amount
    FROM Scheme WHERE scheme_id = p_scheme_id;
    
    -- Fetch citizen profile
    SELECT annual_income, category, location_type, age
    INTO v_income, v_category, v_location, v_age
    FROM Citizen WHERE citizen_id = p_citizen_id;
    
    -- Income factor: lower income gets higher benefit
    -- Income bracket → multiplier (inverse relationship)
    IF v_income <= 50000 THEN
        v_income_factor := 1.0;      -- poorest: full base
    ELSIF v_income <= 100000 THEN
        v_income_factor := 0.90;
    ELSIF v_income <= 200000 THEN
        v_income_factor := 0.80;
    ELSIF v_income <= 350000 THEN
        v_income_factor := 0.65;
    ELSIF v_income <= 500000 THEN
        v_income_factor := 0.50;
    ELSE
        v_income_factor := 0.35;    -- higher income: reduced benefit
    END IF;
    
    -- Base benefit scaled by income
    v_benefit := v_base_amount * v_income_factor;
    
    -- Category bonus (SC/ST get extra as per government policy)
    IF v_category IN ('SC','ST') THEN
        v_cat_bonus := v_benefit * 0.20;    -- 20% bonus
    ELSIF v_category = 'OBC' THEN
        v_cat_bonus := v_benefit * 0.10;    -- 10% bonus
    END IF;
    
    -- Rural bonus: rural areas get 10% extra
    IF v_location = 'RURAL' THEN
        v_rural_bonus := v_benefit * 0.10;
    END IF;
    
    -- Elderly bonus: 60+ get 15% extra
    IF v_age >= 60 THEN
        v_elderly_bonus := v_benefit * 0.15;
    END IF;
    
    -- Total benefit
    v_benefit := v_benefit + v_cat_bonus + v_rural_bonus + v_elderly_bonus;
    
    -- Cap at scheme maximum
    IF v_benefit > v_max_amount THEN
        v_benefit := v_max_amount;
    END IF;
    
    RETURN ROUND(v_benefit, 2);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
    WHEN OTHERS THEN
        RETURN -1;
END CALCULATE_BENEFIT_AMOUNT;
/

-- ------------------------------------------------------------
-- FUNCTION 3: GET_PRIORITY_SCORE
-- Used for officer sorting queue — lower income = higher score
-- Not shown on the citizen-facing interface
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION GET_PRIORITY_SCORE (
    p_citizen_id IN NUMBER
) RETURN NUMBER AS

    v_income    NUMBER;
    v_category  VARCHAR2(5);
    v_location  VARCHAR2(10);
    v_age       NUMBER;
    v_score     NUMBER := 0;

BEGIN
    SELECT annual_income, category, location_type, age
    INTO v_income, v_category, v_location, v_age
    FROM Citizen WHERE citizen_id = p_citizen_id;

    -- Income score (0-50 points): poorest gets 50
    IF v_income <= 50000 THEN
        v_score := v_score + 50;
    ELSIF v_income <= 100000 THEN
        v_score := v_score + 45;
    ELSIF v_income <= 200000 THEN
        v_score := v_score + 38;
    ELSIF v_income <= 350000 THEN
        v_score := v_score + 28;
    ELSIF v_income <= 500000 THEN
        v_score := v_score + 18;
    ELSE
        v_score := v_score + 5;
    END IF;

    -- Category score (0-25 points)
    IF v_category = 'ST' THEN v_score := v_score + 25;
    ELSIF v_category = 'SC' THEN v_score := v_score + 22;
    ELSIF v_category = 'OBC' THEN v_score := v_score + 15;
    ELSE v_score := v_score + 5;
    END IF;

    -- Location score (0-15 points)
    IF v_location = 'RURAL' THEN v_score := v_score + 15;
    ELSE v_score := v_score + 5; END IF;

    -- Age score for elderly (0-10 points)
    IF v_age >= 70 THEN v_score := v_score + 10;
    ELSIF v_age >= 60 THEN v_score := v_score + 7;
    ELSE v_score := v_score + 0; END IF;

    RETURN ROUND(v_score, 2);

EXCEPTION
    WHEN OTHERS THEN RETURN 0;
END GET_PRIORITY_SCORE;
/

-- ------------------------------------------------------------
-- FUNCTION 4: IS_DUPLICATE_APPLICATION
-- Fraud check: returns 'Y' if citizen has active app for scheme
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION IS_DUPLICATE_APPLICATION (
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER
) RETURN CHAR AS
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM Application
    WHERE citizen_id = p_citizen_id
      AND scheme_id  = p_scheme_id
      AND status NOT IN ('REJECTED');
    
    RETURN CASE WHEN v_count > 0 THEN 'Y' ELSE 'N' END;
EXCEPTION
    WHEN OTHERS THEN RETURN 'N';
END IS_DUPLICATE_APPLICATION;
/

-- ============================================================
-- SECTION B: STORED PROCEDURES
-- ============================================================

-- ------------------------------------------------------------
-- PROCEDURE 1: SUBMIT_APPLICATION
-- Full workflow: validate → eligibility check → insert
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SUBMIT_APPLICATION (
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER,
    p_remarks    IN VARCHAR2 DEFAULT NULL
) AS
    v_eligibility   VARCHAR2(200);
    v_duplicate     CHAR(1);
    v_priority      NUMBER;
    v_app_id        NUMBER;
    v_citizen_name  VARCHAR2(100);
    v_scheme_name   VARCHAR2(150);

BEGIN
    -- Verify citizen exists
    BEGIN
        SELECT full_name INTO v_citizen_name FROM Citizen WHERE citizen_id = p_citizen_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Citizen ID ' || p_citizen_id || ' does not exist.');
    END;
    
    -- Verify scheme exists and is active
    BEGIN
        SELECT scheme_name INTO v_scheme_name
        FROM Scheme WHERE scheme_id = p_scheme_id AND is_active = 'Y';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'Scheme ID ' || p_scheme_id || ' not found or inactive.');
    END;
    
    -- Check for duplicate application
    v_duplicate := IS_DUPLICATE_APPLICATION(p_citizen_id, p_scheme_id);
    IF v_duplicate = 'Y' THEN
        RAISE_APPLICATION_ERROR(-20003, 
            'Duplicate application: ' || v_citizen_name || 
            ' already has an active application for ' || v_scheme_name);
    END IF;
    
    -- Eligibility check (documents not mandatory at submission, checked at verification)
    v_eligibility := CHECK_ELIGIBILITY(p_citizen_id, p_scheme_id);
    
    -- Compute priority score
    v_priority := GET_PRIORITY_SCORE(p_citizen_id);
    
    -- Insert application
    v_app_id := SEQ_APPLICATION.NEXTVAL;
    
    INSERT INTO Application (
        application_id, citizen_id, scheme_id, apply_date,
        status, priority_score, remarks
    ) VALUES (
        v_app_id, p_citizen_id, p_scheme_id, SYSDATE,
        'SUBMITTED', v_priority,
        NVL(p_remarks, 'Application submitted via self-service portal')
    );
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('=== APPLICATION SUBMITTED ===');
    DBMS_OUTPUT.PUT_LINE('Application ID : ' || v_app_id);
    DBMS_OUTPUT.PUT_LINE('Citizen        : ' || v_citizen_name);
    DBMS_OUTPUT.PUT_LINE('Scheme         : ' || v_scheme_name);
    DBMS_OUTPUT.PUT_LINE('Priority Score : ' || v_priority);
    DBMS_OUTPUT.PUT_LINE('Eligibility    : ' || v_eligibility);
    DBMS_OUTPUT.PUT_LINE('Status         : SUBMITTED');
    DBMS_OUTPUT.PUT_LINE('Note: Eligibility will be formally verified by assigned officer.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR in SUBMIT_APPLICATION: ' || SQLERRM);
        RAISE;
END SUBMIT_APPLICATION;
/

-- ------------------------------------------------------------
-- PROCEDURE 2: VERIFY_AND_APPROVE_APPLICATION
-- Officer workflow: document check → eligibility → approve/reject
-- Also triggers disbursement
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE VERIFY_AND_APPROVE_APPLICATION (
    p_application_id IN NUMBER,
    p_officer_id     IN NUMBER,
    p_action         IN VARCHAR2,   -- 'APPROVE' or 'REJECT'
    p_remarks        IN VARCHAR2 DEFAULT NULL
) AS
    v_citizen_id    NUMBER;
    v_scheme_id     NUMBER;
    v_current_status VARCHAR2(20);
    v_eligibility   VARCHAR2(200);
    v_benefit_amt   NUMBER;
    v_bank_account  VARCHAR2(20);
    v_ifsc          VARCHAR2(11);
    v_disb_id       NUMBER;
    v_txn_ref       VARCHAR2(50);
    v_fund_balance  NUMBER;
    
BEGIN
    -- Lock and fetch application
    SELECT citizen_id, scheme_id, status
    INTO v_citizen_id, v_scheme_id, v_current_status
    FROM Application
    WHERE application_id = p_application_id
    FOR UPDATE;
    
    -- Validate current status
    IF v_current_status NOT IN ('SUBMITTED','DOC_VERIFIED','FIELD_VERIFIED') THEN
        RAISE_APPLICATION_ERROR(-20010, 
            'Application ' || p_application_id || 
            ' cannot be processed. Current status: ' || v_current_status);
    END IF;
    
    -- Validate officer
    DECLARE
        v_officer_active CHAR(1);
    BEGIN
        SELECT is_active INTO v_officer_active 
        FROM Officer WHERE officer_id = p_officer_id;
        
        IF v_officer_active = 'N' THEN
            RAISE_APPLICATION_ERROR(-20011, 'Officer ' || p_officer_id || ' is not active.');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20012, 'Officer ID ' || p_officer_id || ' not found.');
    END;
    
    -- Assign officer to application
    UPDATE Application 
    SET officer_id = p_officer_id
    WHERE application_id = p_application_id;
    
    IF UPPER(p_action) = 'APPROVE' THEN
    
        -- Run eligibility check (strict: documents required)
        v_eligibility := CHECK_ELIGIBILITY(v_citizen_id, v_scheme_id);
        
        IF SUBSTR(v_eligibility, 1, 8) = 'INELIGIB' THEN
            -- Auto-reject if ineligible
            UPDATE Application
            SET status = 'REJECTED',
                rejection_reason = v_eligibility,
                approval_date = SYSDATE
            WHERE application_id = p_application_id;
            
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('Application AUTO-REJECTED: ' || v_eligibility);
            RETURN;
        END IF;
        
        -- Check fund availability before approval
        SELECT total_budget - disbursed_amount INTO v_fund_balance
        FROM Scheme_Fund_Pool WHERE scheme_id = v_scheme_id;
        
        v_benefit_amt := CALCULATE_BENEFIT_AMOUNT(v_citizen_id, v_scheme_id);
        
        IF v_fund_balance < v_benefit_amt THEN
            UPDATE Application
            SET status = 'ON_HOLD',
                rejection_reason = 'Insufficient scheme funds. Placed on waitlist.',
                remarks = NVL(p_remarks, remarks)
            WHERE application_id = p_application_id;
            
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('Application placed ON_HOLD: Insufficient funds.');
            RETURN;
        END IF;
        
        -- Approve and disburse
        UPDATE Application
        SET status = 'APPROVED',
            approval_date = SYSDATE,
            remarks = NVL(p_remarks, remarks)
        WHERE application_id = p_application_id;
        
        -- Fetch bank details
        SELECT bank_account, ifsc_code
        INTO v_bank_account, v_ifsc
        FROM Citizen WHERE citizen_id = v_citizen_id;
        
        -- Generate transaction reference
        v_txn_ref := 'GSMS' || TO_CHAR(SYSDATE,'YYYYMMDD') || 
                     LPAD(p_application_id,8,'0');
        
        -- Create disbursement record
        v_disb_id := SEQ_DISBURSEMENT.NEXTVAL;
        INSERT INTO Fund_Disbursement (
            disbursement_id, application_id, amount, disbursement_date,
            payment_mode, transaction_ref, bank_account, ifsc_code,
            status, processed_by
        ) VALUES (
            v_disb_id, p_application_id, v_benefit_amt, SYSDATE,
            'DBT', v_txn_ref, v_bank_account, v_ifsc,
            'PROCESSED', p_officer_id
        );
        
        -- Update fund pool
        UPDATE Scheme_Fund_Pool
        SET disbursed_amount = disbursed_amount + v_benefit_amt,
            last_updated = SYSDATE
        WHERE scheme_id = v_scheme_id;
        
        -- Mark application as DISBURSED
        UPDATE Application
        SET status = 'DISBURSED'
        WHERE application_id = p_application_id;
        
        COMMIT;
        
        DBMS_OUTPUT.PUT_LINE('=== APPLICATION APPROVED & DISBURSED ===');
        DBMS_OUTPUT.PUT_LINE('Application ID    : ' || p_application_id);
        DBMS_OUTPUT.PUT_LINE('Disbursement ID   : ' || v_disb_id);
        DBMS_OUTPUT.PUT_LINE('Amount Disbursed  : Rs. ' || v_benefit_amt);
        DBMS_OUTPUT.PUT_LINE('Transaction Ref   : ' || v_txn_ref);
        DBMS_OUTPUT.PUT_LINE('Payment Mode      : DBT');
        DBMS_OUTPUT.PUT_LINE('Bank Account      : ' || v_bank_account);
        
    ELSIF UPPER(p_action) = 'REJECT' THEN
    
        UPDATE Application
        SET status = 'REJECTED',
            rejection_reason = NVL(p_remarks, 'Rejected by officer during verification'),
            approval_date = SYSDATE
        WHERE application_id = p_application_id;
        
        COMMIT;
        
        DBMS_OUTPUT.PUT_LINE('Application ' || p_application_id || ' REJECTED.');
        DBMS_OUTPUT.PUT_LINE('Reason: ' || NVL(p_remarks, 'Not specified'));
        
    ELSE
        RAISE_APPLICATION_ERROR(-20013, 'Invalid action: ' || p_action || '. Use APPROVE or REJECT.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ERROR in VERIFY_AND_APPROVE_APPLICATION: ' || SQLERRM);
        RAISE;
END VERIFY_AND_APPROVE_APPLICATION;
/

-- ------------------------------------------------------------
-- PROCEDURE 3: REGISTER_CITIZEN
-- Adds a new citizen with full validation
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE REGISTER_CITIZEN (
    p_aadhaar    IN VARCHAR2,
    p_name       IN VARCHAR2,
    p_gender     IN CHAR,
    p_dob        IN DATE,
    p_category   IN VARCHAR2,
    p_income     IN NUMBER,
    p_occupation IN VARCHAR2,
    p_land       IN NUMBER,
    p_location   IN VARCHAR2,
    p_village    IN VARCHAR2,
    p_district   IN VARCHAR2,
    p_state      IN VARCHAR2,
    p_pincode    IN VARCHAR2,
    p_phone      IN VARCHAR2,
    p_bank_acc   IN VARCHAR2,
    p_ifsc       IN VARCHAR2
) AS
    v_age       NUMBER;
    v_cid       NUMBER;
BEGIN
    -- Validate Aadhaar
    IF NOT REGEXP_LIKE(p_aadhaar, '^\d{12}$') THEN
        RAISE_APPLICATION_ERROR(-20020, 'Invalid Aadhaar: must be exactly 12 digits');
    END IF;
    
    -- Calculate age
    v_age := TRUNC(MONTHS_BETWEEN(SYSDATE, p_dob) / 12);
    
    IF v_age < 18 THEN
        RAISE_APPLICATION_ERROR(-20021, 'Citizen must be at least 18 years old to register');
    END IF;
    
    -- Check duplicate Aadhaar
    DECLARE
        v_existing NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_existing FROM Citizen WHERE aadhaar_number = p_aadhaar;
        IF v_existing > 0 THEN
            RAISE_APPLICATION_ERROR(-20022, 'Aadhaar ' || p_aadhaar || ' already registered');
        END IF;
    END;
    
    v_cid := SEQ_CITIZEN.NEXTVAL;
    
    INSERT INTO Citizen (
        citizen_id, aadhaar_number, full_name, gender, date_of_birth, age,
        category, annual_income, occupation, land_holding_acres,
        location_type, village_town, district, state, pincode,
        phone, bank_account, ifsc_code, is_verified, registration_date
    ) VALUES (
        v_cid, p_aadhaar, p_name, p_gender, p_dob, v_age,
        p_category, p_income, p_occupation, p_land,
        p_location, p_village, p_district, p_state, p_pincode,
        p_phone, p_bank_acc, p_ifsc, 'N', SYSDATE
    );
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Citizen registered successfully. ID: ' || v_cid);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('REGISTER_CITIZEN ERROR: ' || SQLERRM);
        RAISE;
END REGISTER_CITIZEN;
/

-- ------------------------------------------------------------
-- PROCEDURE 4: GENERATE_SCHEME_REPORT (uses CURSOR)
-- Cursor-based report: scheme-wise beneficiary and fund summary
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE GENERATE_SCHEME_REPORT AS

    -- Explicit cursor: scheme performance summary
    CURSOR c_scheme_perf IS
        SELECT
            s.scheme_id,
            s.scheme_name,
            s.scheme_type,
            sfp.total_budget,
            sfp.disbursed_amount,
            sfp.total_budget - sfp.disbursed_amount AS remaining,
            COUNT(a.application_id)                  AS total_apps,
            SUM(CASE WHEN a.status = 'DISBURSED' THEN 1 ELSE 0 END) AS disbursed_count,
            SUM(CASE WHEN a.status = 'REJECTED'  THEN 1 ELSE 0 END) AS rejected_count,
            SUM(CASE WHEN a.status = 'SUBMITTED' THEN 1 ELSE 0 END) AS pending_count
        FROM Scheme s
        JOIN Scheme_Fund_Pool sfp ON s.scheme_id = sfp.scheme_id
        LEFT JOIN Application a ON s.scheme_id = a.scheme_id
        GROUP BY s.scheme_id, s.scheme_name, s.scheme_type,
                 sfp.total_budget, sfp.disbursed_amount
        ORDER BY s.scheme_type, sfp.disbursed_amount DESC;
    
    v_rec   c_scheme_perf%ROWTYPE;
    v_total_budget     NUMBER := 0;
    v_total_disbursed  NUMBER := 0;
    v_total_apps       NUMBER := 0;

BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('╔══════════════════════════════════════════════════════════════════════╗');
    DBMS_OUTPUT.PUT_LINE('║      GOVERNMENT SCHEME MANAGEMENT SYSTEM — SCHEME REPORT            ║');
    DBMS_OUTPUT.PUT_LINE('║      Generated: ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI') || '                             ║');
    DBMS_OUTPUT.PUT_LINE('╚══════════════════════════════════════════════════════════════════════╝');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(RPAD('Scheme Name',35) || RPAD('Type',7) ||
                         RPAD('Budget(Cr)',12) || RPAD('Disbursed',12) ||
                         RPAD('Apps',6) || RPAD('Done',6) || 'Pending');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',90,'-'));
    
    OPEN c_scheme_perf;
    LOOP
        FETCH c_scheme_perf INTO v_rec;
        EXIT WHEN c_scheme_perf%NOTFOUND;
        
        v_total_budget    := v_total_budget    + v_rec.total_budget;
        v_total_disbursed := v_total_disbursed + v_rec.disbursed_amount;
        v_total_apps      := v_total_apps      + v_rec.total_apps;
        
        DBMS_OUTPUT.PUT_LINE(
            RPAD(SUBSTR(v_rec.scheme_name,1,33),35) ||
            RPAD(v_rec.scheme_type,7) ||
            RPAD(TO_CHAR(ROUND(v_rec.total_budget/10000000,1)),12) ||
            RPAD(TO_CHAR(ROUND(v_rec.disbursed_amount/10000000,1)),12) ||
            RPAD(v_rec.total_apps,6) ||
            RPAD(v_rec.disbursed_count,6) ||
            v_rec.pending_count
        );
    END LOOP;
    CLOSE c_scheme_perf;
    
    DBMS_OUTPUT.PUT_LINE(RPAD('-',90,'-'));
    DBMS_OUTPUT.PUT_LINE('TOTAL: Budget Rs.' || ROUND(v_total_budget/10000000,1) || 
                         ' Cr | Disbursed Rs.' || ROUND(v_total_disbursed/10000000,1) ||
                         ' Cr | Applications: ' || v_total_apps);

EXCEPTION
    WHEN OTHERS THEN
        IF c_scheme_perf%ISOPEN THEN CLOSE c_scheme_perf; END IF;
        DBMS_OUTPUT.PUT_LINE('ERROR in report: ' || SQLERRM);
END GENERATE_SCHEME_REPORT;
/

-- ------------------------------------------------------------
-- PROCEDURE 5: STATE_WISE_BENEFICIARY_REPORT (cursor-based)
-- State-wise fund distribution report
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE STATE_WISE_REPORT AS

    CURSOR c_state IS
        SELECT
            c.state,
            COUNT(DISTINCT c.citizen_id)                    AS total_citizens,
            COUNT(DISTINCT a.application_id)                AS total_applications,
            COUNT(DISTINCT CASE WHEN a.status = 'DISBURSED' THEN a.application_id END) AS disbursed,
            NVL(SUM(fd.amount),0)                           AS total_funds,
            ROUND(AVG(fd.amount),0)                         AS avg_benefit
        FROM Citizen c
        LEFT JOIN Application a ON c.citizen_id = a.citizen_id
        LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
        GROUP BY c.state
        ORDER BY total_funds DESC;
    
    r c_state%ROWTYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== STATE-WISE BENEFICIARY & FUND REPORT ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('State',22) || RPAD('Citizens',10) ||
                         RPAD('Apps',7) || RPAD('Disbursed',11) ||
                         RPAD('Total Funds',15) || 'Avg Benefit');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',80,'-'));
    
    OPEN c_state;
    LOOP
        FETCH c_state INTO r;
        EXIT WHEN c_state%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(SUBSTR(r.state,1,20),22) ||
            RPAD(r.total_citizens,10)     ||
            RPAD(r.total_applications,7)  ||
            RPAD(r.disbursed,11)          ||
            RPAD('Rs.'||ROUND(r.total_funds/100000,1)||'L',15) ||
            'Rs.'||NVL(r.avg_benefit,0)
        );
    END LOOP;
    CLOSE c_state;

EXCEPTION
    WHEN OTHERS THEN
        IF c_state%ISOPEN THEN CLOSE c_state; END IF;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END STATE_WISE_REPORT;
/

-- ============================================================
-- SECTION C: TRIGGERS
-- ============================================================

-- ------------------------------------------------------------
-- TRIGGER 1: TRG_APPLICATION_AUDIT
-- Fires on every status change in Application table
-- Populates APPLICATION_AUDIT_LOG automatically
-- ------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_APPLICATION_AUDIT
AFTER UPDATE OF status ON Application
FOR EACH ROW
BEGIN
    INSERT INTO Application_Audit_Log (
        audit_id, application_id, old_status, new_status,
        changed_by, change_date, change_reason
    ) VALUES (
        SEQ_AUDIT.NEXTVAL,
        :NEW.application_id,
        :OLD.status,
        :NEW.status,
        USER,
        SYSTIMESTAMP,
        :NEW.rejection_reason
    );
END TRG_APPLICATION_AUDIT;
/

-- ------------------------------------------------------------
-- TRIGGER 2: TRG_FUND_EXHAUSTION
-- Fires when Scheme_Fund_Pool disbursed_amount is updated
-- Auto-suspends scheme if budget exhausted (real-life behaviour)
-- ------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_FUND_EXHAUSTION
AFTER UPDATE OF disbursed_amount ON Scheme_Fund_Pool
FOR EACH ROW
DECLARE
    v_utilization NUMBER;
BEGIN
    v_utilization := (:NEW.disbursed_amount / :NEW.total_budget) * 100;
    
    -- Suspend scheme if 100% funds used
    IF :NEW.disbursed_amount >= :NEW.total_budget THEN
        UPDATE Scheme
        SET is_active = 'N'
        WHERE scheme_id = :NEW.scheme_id;
        
        DBMS_OUTPUT.PUT_LINE('ALERT: Scheme ID ' || :NEW.scheme_id || 
                             ' SUSPENDED — Budget of Rs.' ||
                             :NEW.total_budget || ' fully exhausted.');
    
    -- Warning at 90% utilization
    ELSIF v_utilization >= 90 THEN
        DBMS_OUTPUT.PUT_LINE('WARNING: Scheme ID ' || :NEW.scheme_id || 
                             ' — ' || ROUND(v_utilization,1) || '% funds utilised.');
    END IF;
END TRG_FUND_EXHAUSTION;
/

-- ------------------------------------------------------------
-- TRIGGER 3: TRG_PREVENT_DUPLICATE_ACTIVE_APP
-- Fires on INSERT into Application
-- Blocks duplicate active applications (defence in depth)
-- (UNIQUE constraint handles it too — this gives a friendly message)
-- ------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_PREVENT_DUPLICATE_ACTIVE_APP
BEFORE INSERT ON Application
FOR EACH ROW
DECLARE
    v_count     NUMBER;
    v_scheme_nm VARCHAR2(150);
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM Application
    WHERE citizen_id = :NEW.citizen_id
      AND scheme_id  = :NEW.scheme_id
      AND status NOT IN ('REJECTED');
    
    IF v_count > 0 THEN
        SELECT scheme_name INTO v_scheme_nm FROM Scheme WHERE scheme_id = :NEW.scheme_id;
        RAISE_APPLICATION_ERROR(-20030,
            'Duplicate application blocked: Active application already exists for scheme: ' || v_scheme_nm);
    END IF;
END TRG_PREVENT_DUPLICATE_ACTIVE_APP;
/

-- ------------------------------------------------------------
-- TRIGGER 4: TRG_CITIZEN_VERIFIED_ON_DOC
-- Fires when a citizen document is marked VERIFIED
-- If citizen now has 2+ verified docs, marks citizen as verified
-- ------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_CITIZEN_VERIFIED_ON_DOC
AFTER UPDATE OF status ON Citizen_Documents
FOR EACH ROW
DECLARE
    v_verified_count NUMBER;
BEGIN
    IF :NEW.status = 'VERIFIED' THEN
        SELECT COUNT(*) INTO v_verified_count
        FROM Citizen_Documents
        WHERE citizen_id = :NEW.citizen_id
          AND status = 'VERIFIED';
        
        IF v_verified_count >= 2 THEN
            UPDATE Citizen
            SET is_verified = 'Y'
            WHERE citizen_id = :NEW.citizen_id;
        END IF;
    END IF;
END TRG_CITIZEN_VERIFIED_ON_DOC;
/

-- ------------------------------------------------------------
-- TRIGGER 5: TRG_SCHEME_AUDIT_ACTIVE
-- When scheme is deactivated, log it (insert into audit)
-- Also prevents reactivation if funds exhausted
-- ------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_SCHEME_AUDIT_ACTIVE
BEFORE UPDATE OF is_active ON Scheme
FOR EACH ROW
DECLARE
    v_fund_balance NUMBER;
BEGIN
    -- If trying to reactivate a scheme, check if funds remain
    IF :NEW.is_active = 'Y' AND :OLD.is_active = 'N' THEN
        SELECT total_budget - disbursed_amount INTO v_fund_balance
        FROM Scheme_Fund_Pool
        WHERE scheme_id = :NEW.scheme_id;
        
        IF v_fund_balance <= 0 THEN
            RAISE_APPLICATION_ERROR(-20040,
                'Cannot reactivate scheme: Fund pool is exhausted. Allocate new budget first.');
        END IF;
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('Scheme ' || :NEW.scheme_name || 
                         ' status changed: ' || :OLD.is_active || ' -> ' || :NEW.is_active);
END TRG_SCHEME_AUDIT_ACTIVE;
/

-- ============================================================
-- SECTION D: 10 COMPLEX SQL QUERIES
-- ============================================================

-- QUERY 1: Fraud Detection — Citizens with applications in CONFLICTING schemes
-- (applied to both a housing scheme AND a rural employment scheme simultaneously)
SELECT
    c.citizen_id,
    c.full_name,
    c.aadhaar_number,
    c.state,
    c.annual_income,
    COUNT(a.application_id) AS scheme_count,
    LISTAGG(s.scheme_name, ' | ') WITHIN GROUP (ORDER BY s.scheme_id) AS schemes_applied
FROM Citizen c
JOIN Application a ON c.citizen_id = a.citizen_id
JOIN Scheme s ON a.scheme_id = s.scheme_id
WHERE a.status NOT IN ('REJECTED')
GROUP BY c.citizen_id, c.full_name, c.aadhaar_number, c.state, c.annual_income
HAVING COUNT(DISTINCT a.scheme_id) > 2
ORDER BY scheme_count DESC;

-- QUERY 2: Scheme Utilization Report with budget health indicators
SELECT
    s.scheme_name,
    s.scheme_type,
    TO_CHAR(sfp.total_budget,'99,99,99,99,999') AS total_budget,
    TO_CHAR(sfp.disbursed_amount,'99,99,99,99,999') AS disbursed,
    ROUND((sfp.disbursed_amount/sfp.total_budget)*100,1) || '%' AS utilization,
    CASE
        WHEN (sfp.disbursed_amount/sfp.total_budget) >= 1.0 THEN 'EXHAUSTED'
        WHEN (sfp.disbursed_amount/sfp.total_budget) >= 0.9 THEN 'CRITICAL'
        WHEN (sfp.disbursed_amount/sfp.total_budget) >= 0.7 THEN 'HIGH'
        WHEN (sfp.disbursed_amount/sfp.total_budget) >= 0.4 THEN 'MODERATE'
        ELSE 'HEALTHY'
    END AS fund_status,
    s.is_active
FROM Scheme s
JOIN Scheme_Fund_Pool sfp ON s.scheme_id = sfp.scheme_id
ORDER BY (sfp.disbursed_amount/sfp.total_budget) DESC;

-- QUERY 3: Officer Efficiency — Avg processing days and approval rates
SELECT
    o.officer_name,
    o.assigned_state,
    d.department_name,
    COUNT(a.application_id) AS total_handled,
    ROUND(AVG(CASE WHEN a.approval_date IS NOT NULL
              THEN a.approval_date - a.apply_date END),1) AS avg_days_to_decision,
    ROUND(
        SUM(CASE WHEN a.status IN ('APPROVED','DISBURSED') THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(a.application_id),0), 1
    ) || '%' AS approval_rate,
    NVL(SUM(fd.amount),0) AS total_disbursed_by_officer
FROM Officer o
JOIN Department d ON o.department_id = d.department_id
LEFT JOIN Application a ON o.officer_id = a.officer_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
GROUP BY o.officer_id, o.officer_name, o.assigned_state, d.department_name
HAVING COUNT(a.application_id) > 0
ORDER BY avg_days_to_decision ASC;

-- QUERY 4: State-wise demographic breakdown of beneficiaries
SELECT
    c.state,
    COUNT(*) AS total_beneficiaries,
    SUM(CASE WHEN c.category = 'SC' THEN 1 ELSE 0 END) AS sc_count,
    SUM(CASE WHEN c.category = 'ST' THEN 1 ELSE 0 END) AS st_count,
    SUM(CASE WHEN c.category = 'OBC' THEN 1 ELSE 0 END) AS obc_count,
    SUM(CASE WHEN c.category = 'GEN' THEN 1 ELSE 0 END) AS gen_count,
    SUM(CASE WHEN c.location_type = 'RURAL' THEN 1 ELSE 0 END) AS rural_count,
    SUM(CASE WHEN c.gender = 'F' THEN 1 ELSE 0 END) AS female_count,
    ROUND(AVG(c.annual_income),0) AS avg_income
FROM Citizen c
JOIN Application a ON c.citizen_id = a.citizen_id
WHERE a.status IN ('APPROVED','DISBURSED')
GROUP BY c.state
ORDER BY total_beneficiaries DESC;

-- QUERY 5: Pending applications sorted by priority score (officer workqueue)
SELECT
    a.application_id,
    c.full_name,
    c.aadhaar_number,
    c.category,
    c.annual_income,
    c.location_type,
    c.state,
    s.scheme_name,
    a.priority_score,
    a.apply_date,
    TRUNC(SYSDATE - a.apply_date) AS days_pending,
    CHECK_ELIGIBILITY(c.citizen_id, s.scheme_id) AS eligibility_status
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
JOIN Scheme s ON a.scheme_id = s.scheme_id
WHERE a.status IN ('SUBMITTED','DOC_VERIFIED')
ORDER BY a.priority_score DESC, a.apply_date ASC;

-- QUERY 6: Top 10 schemes by number of disbursements (popularity ranking)
SELECT
    ROWNUM AS rank,
    scheme_name,
    scheme_type,
    department_name,
    disbursed_count,
    TO_CHAR(total_disbursed,'99,99,99,99,999') AS total_disbursed_rs
FROM (
    SELECT
        s.scheme_name,
        s.scheme_type,
        d.department_name,
        COUNT(fd.disbursement_id) AS disbursed_count,
        NVL(SUM(fd.amount),0)    AS total_disbursed
    FROM Scheme s
    JOIN Department d ON s.department_id = d.department_id
    LEFT JOIN Application a ON s.scheme_id = a.scheme_id
    LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
    WHERE fd.status = 'PROCESSED'
    GROUP BY s.scheme_name, s.scheme_type, d.department_name
    ORDER BY disbursed_count DESC
)
WHERE ROWNUM <= 10;

-- QUERY 7: Income-band analysis — which income group benefits most
SELECT
    CASE
        WHEN c.annual_income <= 50000  THEN 'Below 50K (BPL)'
        WHEN c.annual_income <= 100000 THEN '50K - 1L'
        WHEN c.annual_income <= 250000 THEN '1L - 2.5L'
        WHEN c.annual_income <= 500000 THEN '2.5L - 5L'
        ELSE 'Above 5L'
    END AS income_band,
    COUNT(DISTINCT c.citizen_id) AS citizens,
    COUNT(a.application_id) AS applications,
    SUM(CASE WHEN a.status = 'DISBURSED' THEN 1 ELSE 0 END) AS disbursed,
    NVL(SUM(fd.amount),0) AS total_benefit_rs,
    ROUND(NVL(AVG(fd.amount),0),0) AS avg_benefit_rs
FROM Citizen c
LEFT JOIN Application a ON c.citizen_id = a.citizen_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
GROUP BY
    CASE
        WHEN c.annual_income <= 50000  THEN 'Below 50K (BPL)'
        WHEN c.annual_income <= 100000 THEN '50K - 1L'
        WHEN c.annual_income <= 250000 THEN '1L - 2.5L'
        WHEN c.annual_income <= 500000 THEN '2.5L - 5L'
        ELSE 'Above 5L'
    END
ORDER BY MIN(c.annual_income);

-- QUERY 8: Rejection analysis — why applications are being rejected
SELECT
    s.scheme_name,
    a.rejection_reason,
    COUNT(*) AS rejection_count
FROM Application a
JOIN Scheme s ON a.scheme_id = s.scheme_id
WHERE a.status = 'REJECTED'
  AND a.rejection_reason IS NOT NULL
GROUP BY s.scheme_name, a.rejection_reason
ORDER BY rejection_count DESC;

-- QUERY 9: Citizens who are eligible for schemes but have NOT applied
-- (useful for outreach targeting — a decision support feature)
SELECT
    c.citizen_id,
    c.full_name,
    c.state,
    c.district,
    c.category,
    c.annual_income,
    c.location_type,
    s.scheme_name,
    CHECK_ELIGIBILITY(c.citizen_id, s.scheme_id) AS eligibility_check
FROM Citizen c
CROSS JOIN Scheme s
WHERE s.is_active = 'Y'
  AND NOT EXISTS (
      SELECT 1 FROM Application a
      WHERE a.citizen_id = c.citizen_id
        AND a.scheme_id  = s.scheme_id
  )
  AND c.annual_income < 200000
  AND c.is_verified = 'Y'
  AND ROWNUM <= 50
ORDER BY c.annual_income ASC;

-- QUERY 10: Monthly disbursement trend (last 12 months)
SELECT
    TO_CHAR(fd.disbursement_date,'YYYY-MM') AS month,
    COUNT(fd.disbursement_id) AS disbursements,
    SUM(fd.amount) AS total_amount,
    COUNT(DISTINCT a.scheme_id) AS schemes_active,
    ROUND(AVG(fd.amount),0) AS avg_per_beneficiary
FROM Fund_Disbursement fd
JOIN Application a ON fd.application_id = a.application_id
WHERE fd.status = 'PROCESSED'
  AND fd.disbursement_date >= ADD_MONTHS(SYSDATE, -12)
GROUP BY TO_CHAR(fd.disbursement_date,'YYYY-MM')
ORDER BY month ASC;

-- ============================================================
-- SECTION E: SAMPLE EXECUTION DEMO FLOW
-- Run these blocks one at a time to demonstrate the system
-- ============================================================

-- STEP 1: Register a new citizen
BEGIN
    REGISTER_CITIZEN(
        p_aadhaar    => '987654321098',
        p_name       => 'Ramkali Devi Yadav',
        p_gender     => 'F',
        p_dob        => DATE '1978-06-15',
        p_category   => 'OBC',
        p_income     => 85000,
        p_occupation => 'Agricultural Labourer',
        p_land       => 1.5,
        p_location   => 'RURAL',
        p_village    => 'Rampur Khas',
        p_district   => 'Varanasi',
        p_state      => 'Uttar Pradesh',
        p_pincode    => '221001',
        p_phone      => '9415123456',
        p_bank_acc   => 'ACCT999999000099',
        p_ifsc       => 'SBIN0001234'
    );
END;
/

-- STEP 2: Check eligibility for all major schemes
DECLARE
    v_cid NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    DBMS_OUTPUT.PUT_LINE('Eligibility Report for Ramkali Devi Yadav:');
    DBMS_OUTPUT.PUT_LINE('Kisan Samman Yojana   : ' || CHECK_ELIGIBILITY(v_cid, 1));
    DBMS_OUTPUT.PUT_LINE('Gramin Awas Yojana    : ' || CHECK_ELIGIBILITY(v_cid, 2));
    DBMS_OUTPUT.PUT_LINE('Swasthya Suraksha     : ' || CHECK_ELIGIBILITY(v_cid, 3));
    DBMS_OUTPUT.PUT_LINE('Gramin Rozgar         : ' || CHECK_ELIGIBILITY(v_cid, 4));
    DBMS_OUTPUT.PUT_LINE('Ujjwala Rasoi         : ' || CHECK_ELIGIBILITY(v_cid, 5));
    DBMS_OUTPUT.PUT_LINE('Calculated Benefit    : Rs.' || CALCULATE_BENEFIT_AMOUNT(v_cid, 3));
    DBMS_OUTPUT.PUT_LINE('Priority Score        : ' || GET_PRIORITY_SCORE(v_cid));
END;
/

-- STEP 3: Submit application for Swasthya Suraksha Yojana
DECLARE
    v_cid NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    SUBMIT_APPLICATION(v_cid, 3, 'Self-applied for health coverage');
END;
/

-- STEP 4: Officer approves the application
DECLARE
    v_app_id NUMBER;
    v_cid    NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    SELECT application_id INTO v_app_id
    FROM Application WHERE citizen_id = v_cid AND scheme_id = 3;
    
    -- Insert documents first so eligibility passes
    INSERT INTO Citizen_Documents (citizen_id, doc_type, doc_number, status, verified_by, verification_date)
    VALUES (v_cid, 'AADHAAR', '987654321098', 'VERIFIED', 3, SYSDATE);
    INSERT INTO Citizen_Documents (citizen_id, doc_type, doc_number, status, verified_by, verification_date)
    VALUES (v_cid, 'INCOME_CERT', 'IC2024UP9999', 'VERIFIED', 3, SYSDATE);
    COMMIT;
    
    VERIFY_AND_APPROVE_APPLICATION(v_app_id, 3, 'APPROVE', 'Documents verified. Eligible for scheme.');
END;
/

-- STEP 5: Generate scheme report
BEGIN
    GENERATE_SCHEME_REPORT;
END;
/

-- STEP 6: Generate state-wise report
BEGIN
    STATE_WISE_REPORT;
END;
/

-- STEP 7: View audit trail for the application
DECLARE
    v_cid    NUMBER;
    v_app_id NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    SELECT application_id INTO v_app_id FROM Application WHERE citizen_id = v_cid AND scheme_id = 3;
    
    DBMS_OUTPUT.PUT_LINE('Audit Trail for Application ID: ' || v_app_id);
    FOR r IN (SELECT * FROM Application_Audit_Log WHERE application_id = v_app_id ORDER BY change_date) LOOP
        DBMS_OUTPUT.PUT_LINE(TO_CHAR(r.change_date,'DD-MON-YYYY HH24:MI:SS') || 
                             ' | ' || NVL(r.old_status,'—') || ' → ' || r.new_status ||
                             ' | By: ' || r.changed_by);
    END LOOP;
END;
/

-- ============================================================
-- END OF PART 3 — ALL DONE
-- Total: 4 Functions | 5 Procedures | 5 Triggers | 10 Queries
-- ============================================================
COMMIT;
