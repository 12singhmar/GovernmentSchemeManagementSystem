-- ============================================================
--  GOVERNMENT SCHEME MANAGEMENT SYSTEM
--  UCS310 - Database Management Systems
--  Group 4 | Thapar Institute of Engineering & Technology
--  Kavya Singal | Ipshita Singla | Akshaj Singhmar
-- ============================================================
-- Oracle SQL + PL/SQL
-- Run on: https://livesql.oracle.com
-- Enable DBMS_OUTPUT before running procedure blocks
-- ============================================================


-- ============================================================
--  PART 1 — TABLE DEFINITIONS (DDL)
-- ============================================================

-- Department table — ministries that own schemes
CREATE TABLE Department (
    department_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name  VARCHAR2(100) NOT NULL UNIQUE,
    department_code  VARCHAR2(10)  NOT NULL UNIQUE,
    ministry         VARCHAR2(100) NOT NULL,
    head_name        VARCHAR2(100),
    established_year NUMBER(4) CHECK (established_year BETWEEN 1947 AND 2025)
);

-- Schemes — both major and minor welfare programmes
CREATE TABLE Scheme (
    scheme_id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scheme_name         VARCHAR2(150) NOT NULL UNIQUE,
    scheme_code         VARCHAR2(20)  NOT NULL UNIQUE,
    department_id       NUMBER NOT NULL,
    scheme_type         VARCHAR2(10)  CHECK (scheme_type IN ('MAJOR','MINOR')),
    description         VARCHAR2(500),
    launch_date         DATE NOT NULL,
    base_benefit_amount NUMBER(12,2)  CHECK (base_benefit_amount > 0),
    max_benefit_amount  NUMBER(12,2)  CHECK (max_benefit_amount > 0),
    applicable_states   VARCHAR2(500) DEFAULT 'ALL',
    is_active           CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    CONSTRAINT fk_scheme_dept FOREIGN KEY (department_id) REFERENCES Department(department_id),
    CONSTRAINT chk_benefit CHECK (max_benefit_amount >= base_benefit_amount)
);

-- Eligibility rules per scheme — the rule engine table
-- much better than hardcoding IF-ELSE in PL/SQL
CREATE TABLE Scheme_Eligibility_Rules (
    rule_id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scheme_id          NUMBER NOT NULL,
    min_age            NUMBER(3) DEFAULT 18,
    max_age            NUMBER(3) DEFAULT 120,
    max_income         NUMBER(12,2),
    min_income         NUMBER(12,2) DEFAULT 0,
    allowed_categories VARCHAR2(50) DEFAULT 'ALL',
    location_type      VARCHAR2(10) DEFAULT 'ALL' CHECK (location_type IN ('RURAL','URBAN','ALL')),
    gender_restriction VARCHAR2(5)  DEFAULT 'ALL' CHECK (gender_restriction IN ('M','F','ALL')),
    min_land_acres     NUMBER(6,2)  DEFAULT 0,
    CONSTRAINT fk_rule_scheme FOREIGN KEY (scheme_id) REFERENCES Scheme(scheme_id)
);

-- Fund pool — tracks budget and spending per scheme
CREATE TABLE Scheme_Fund_Pool (
    pool_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scheme_id        NUMBER NOT NULL UNIQUE,
    financial_year   VARCHAR2(10) NOT NULL,
    total_budget     NUMBER(15,2) NOT NULL CHECK (total_budget > 0),
    disbursed_amount NUMBER(15,2) DEFAULT 0,
    last_updated     DATE DEFAULT SYSDATE,
    CONSTRAINT fk_pool_scheme FOREIGN KEY (scheme_id) REFERENCES Scheme(scheme_id)
);

-- Officers — government staff who verify and approve
CREATE TABLE Officer (
    officer_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    officer_name     VARCHAR2(100) NOT NULL,
    employee_code    VARCHAR2(20)  NOT NULL UNIQUE,
    department_id    NUMBER NOT NULL,
    designation      VARCHAR2(100),
    assigned_district VARCHAR2(100) NOT NULL,
    assigned_state   VARCHAR2(100) NOT NULL,
    phone            VARCHAR2(15),
    join_date        DATE NOT NULL,
    is_active        CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    CONSTRAINT fk_officer_dept FOREIGN KEY (department_id) REFERENCES Department(department_id)
);

-- Citizens — the core beneficiary table
CREATE TABLE Citizen (
    citizen_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    aadhaar_number     CHAR(12) NOT NULL UNIQUE,
    full_name          VARCHAR2(100) NOT NULL,
    gender             CHAR(1) NOT NULL CHECK (gender IN ('M','F')),
    date_of_birth      DATE NOT NULL,
    age                NUMBER(3) CHECK (age BETWEEN 0 AND 120),
    category           VARCHAR2(5) NOT NULL CHECK (category IN ('SC','ST','OBC','GEN')),
    annual_income      NUMBER(12,2) NOT NULL CHECK (annual_income >= 0),
    occupation         VARCHAR2(100),
    land_holding_acres NUMBER(6,2) DEFAULT 0,
    location_type      VARCHAR2(10) NOT NULL CHECK (location_type IN ('RURAL','URBAN')),
    village_town       VARCHAR2(100) NOT NULL,
    district           VARCHAR2(100) NOT NULL,
    state              VARCHAR2(100) NOT NULL,
    pincode            VARCHAR2(6),
    phone              VARCHAR2(15),
    bank_account       VARCHAR2(20) NOT NULL UNIQUE,
    ifsc_code          VARCHAR2(11) NOT NULL,
    is_verified        CHAR(1) DEFAULT 'N' CHECK (is_verified IN ('Y','N')),
    registration_date  DATE DEFAULT SYSDATE,
    CONSTRAINT chk_aadhaar CHECK (REGEXP_LIKE(aadhaar_number, '^\d{12}$'))
);

-- Documents uploaded by citizen
CREATE TABLE Citizen_Documents (
    doc_id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    citizen_id        NUMBER NOT NULL,
    doc_type          VARCHAR2(50) NOT NULL CHECK (doc_type IN (
                        'AADHAAR','INCOME_CERT','CASTE_CERT',
                        'LAND_RECORD','BANK_PASSBOOK','RATION_CARD')),
    doc_number        VARCHAR2(50),
    upload_date       DATE DEFAULT SYSDATE,
    status            VARCHAR2(15) DEFAULT 'PENDING'
                        CHECK (status IN ('PENDING','VERIFIED','REJECTED')),
    verified_by       NUMBER,
    CONSTRAINT fk_doc_citizen FOREIGN KEY (citizen_id) REFERENCES Citizen(citizen_id),
    CONSTRAINT fk_doc_officer FOREIGN KEY (verified_by) REFERENCES Officer(officer_id)
);

-- Application — heart of the workflow
CREATE TABLE Application (
    application_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    citizen_id       NUMBER NOT NULL,
    scheme_id        NUMBER NOT NULL,
    officer_id       NUMBER,
    apply_date       DATE DEFAULT SYSDATE NOT NULL,
    status           VARCHAR2(20) DEFAULT 'SUBMITTED'
                        CHECK (status IN ('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','DISBURSED')),
    priority_score   NUMBER(5,2) DEFAULT 0,
    rejection_reason VARCHAR2(300),
    approval_date    DATE,
    remarks          VARCHAR2(400),
    CONSTRAINT fk_app_citizen FOREIGN KEY (citizen_id) REFERENCES Citizen(citizen_id),
    CONSTRAINT fk_app_scheme  FOREIGN KEY (scheme_id)  REFERENCES Scheme(scheme_id),
    CONSTRAINT fk_app_officer FOREIGN KEY (officer_id) REFERENCES Officer(officer_id),
    CONSTRAINT uq_citizen_scheme UNIQUE (citizen_id, scheme_id)
);

-- Fund disbursement — DBT simulation
CREATE TABLE Fund_Disbursement (
    disbursement_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id   NUMBER NOT NULL UNIQUE,
    amount           NUMBER(12,2) NOT NULL CHECK (amount > 0),
    disbursement_date DATE DEFAULT SYSDATE,
    payment_mode     VARCHAR2(10) DEFAULT 'DBT'
                        CHECK (payment_mode IN ('DBT','NEFT','RTGS')),
    transaction_ref  VARCHAR2(50) UNIQUE,
    bank_account     VARCHAR2(20) NOT NULL,
    status           VARCHAR2(15) DEFAULT 'PROCESSED'
                        CHECK (status IN ('PROCESSED','FAILED')),
    CONSTRAINT fk_disb_app FOREIGN KEY (application_id) REFERENCES Application(application_id)
);

-- Audit log — auto-populated by trigger on every status change
CREATE TABLE Application_Audit_Log (
    audit_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id NUMBER NOT NULL,
    old_status     VARCHAR2(20),
    new_status     VARCHAR2(20) NOT NULL,
    changed_by     VARCHAR2(100) DEFAULT USER,
    change_date    TIMESTAMP DEFAULT SYSTIMESTAMP,
    CONSTRAINT fk_audit_app FOREIGN KEY (application_id) REFERENCES Application(application_id)
);


-- ============================================================
--  PART 2 — MASTER DATA (Departments, Schemes, Officers)
-- ============================================================

-- Departments
INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of Agriculture & Farmers Welfare', 'MOA', 'Agriculture', 'Shivraj Singh Chouhan', 1947);

INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of Housing & Urban Affairs', 'MOHUA', 'Housing', 'Manohar Lal Khattar', 1952);

INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of Health & Family Welfare', 'MOHFW', 'Health', 'JP Nadda', 1947);

INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of Rural Development', 'MRD', 'Rural Development', 'Shivraj Singh Chouhan', 1952);

INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of Women & Child Development', 'MWCD', 'WCD', 'Annpurna Devi', 1985);

INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of Social Justice', 'MSJE', 'Social Justice', 'Virendra Kumar', 1998);

INSERT INTO Department (department_name, department_code, ministry, head_name, established_year)
VALUES ('Ministry of New & Renewable Energy', 'MNRE', 'Energy', 'Pralhad Joshi', 1992);

COMMIT;

-- Schemes (dept IDs will be 1-7 in order of insert above)
-- 5 major schemes
INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Kisan Samman Yojana', 'KSY-2019', 1, 'MAJOR',
'Annual income support for small and marginal farmers. Paid in three instalments via DBT.',
DATE '2019-02-24', 6000, 8000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Gramin Awas Yojana', 'GAY-2016', 2, 'MAJOR',
'Housing subsidy for rural BPL families to build pucca houses.',
DATE '2016-11-20', 120000, 250000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Swasthya Suraksha Yojana', 'SSY-2018', 3, 'MAJOR',
'Health insurance coverage upto 5 lakh per family per year for economically weaker sections.',
DATE '2018-09-23', 300000, 500000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Gramin Rozgar Guarantee Scheme', 'GRGS-2005', 4, 'MAJOR',
'Guarantees 100 days of wage employment per year to rural adult households.',
DATE '2005-02-02', 15000, 25000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Ujjwala Rasoi Yojana', 'URY-2016', 4, 'MAJOR',
'Free LPG connections for BPL women in rural areas to reduce dependence on firewood.',
DATE '2016-05-01', 1600, 3200);

-- 5 minor schemes
INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Surya Shakti Solar Subsidy', 'SSSS-2024', 7, 'MINOR',
'Rooftop solar panel subsidy for households to cut electricity bills.',
DATE '2024-02-13', 30000, 78000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Naari Shakti Udyam Yojana', 'NSUY-2020', 5, 'MINOR',
'Micro-enterprise support and training for women from SC/ST/OBC backgrounds.',
DATE '2020-03-08', 50000, 100000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('SC ST Scholarship Scheme', 'SCSS-2008', 6, 'MINOR',
'Merit-cum-means scholarship for SC/ST students in higher education.',
DATE '2008-07-01', 12000, 36000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Kisan Yantra Anudan', 'KYA-2021', 1, 'MINOR',
'Subsidy on modern farming equipment for small and marginal farmers.',
DATE '2021-06-01', 25000, 100000);

INSERT INTO Scheme (scheme_name, scheme_code, department_id, scheme_type, description, launch_date, base_benefit_amount, max_benefit_amount)
VALUES ('Divyang Sahayata Yojana', 'DSY-2015', 6, 'MINOR',
'Assistive devices and monthly pension for persons with benchmark disabilities.',
DATE '2015-12-03', 3000, 10000);

COMMIT;

-- Eligibility rules (one row per scheme)
-- scheme_id 1 = KSY (farmers, income < 2.5L, land 0.1-5 acres)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type, min_land_acres)
VALUES (1, 18, 75, 250000, 'ALL', 'ALL', 0.1);

-- scheme_id 2 = GAY (rural, income < 3L)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type)
VALUES (2, 21, 70, 300000, 'ALL', 'RURAL');

-- scheme_id 3 = SSY (income < 5L, all)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type)
VALUES (3, 0, 120, 500000, 'ALL', 'ALL');

-- scheme_id 4 = GRGS (rural adults, any income)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, allowed_categories, location_type)
VALUES (4, 18, 60, 'ALL', 'RURAL');

-- scheme_id 5 = URY (women, BPL, income < 2L)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type, gender_restriction)
VALUES (5, 18, 120, 200000, 'ALL', 'ALL', 'F');

-- scheme_id 6 = Solar (income 1L-15L, homeowners)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, min_income, allowed_categories, location_type)
VALUES (6, 21, 120, 1500000, 100000, 'ALL', 'ALL');

-- scheme_id 7 = NSUY (women SC/ST/OBC, income < 5L)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type, gender_restriction)
VALUES (7, 18, 55, 500000, 'SC,ST,OBC', 'ALL', 'F');

-- scheme_id 8 = SCSS (SC/ST students, income < 2.5L)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type)
VALUES (8, 18, 30, 250000, 'SC,ST', 'ALL');

-- scheme_id 9 = KYA (farmers with land)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, max_income, allowed_categories, location_type, min_land_acres)
VALUES (9, 18, 70, 350000, 'ALL', 'ALL', 0.5);

-- scheme_id 10 = DSY (anyone with disability)
INSERT INTO Scheme_Eligibility_Rules (scheme_id, min_age, max_age, allowed_categories, location_type)
VALUES (10, 0, 120, 'ALL', 'ALL');

COMMIT;

-- Fund pools for all 10 schemes
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (1,  '2024-25', 75000000000, 0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (2,  '2024-25', 54000000000, 0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (3,  '2024-25', 76000000000, 0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (4,  '2024-25', 89000000000, 0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (5,  '2024-25', 16000000000, 0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (6,  '2024-25', 7500000000,  0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (7,  '2024-25', 2000000000,  0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (8,  '2024-25', 4500000000,  0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (9,  '2024-25', 3500000000,  0);
INSERT INTO Scheme_Fund_Pool (scheme_id, financial_year, total_budget, disbursed_amount)
VALUES (10, '2024-25', 800000000,   0);

COMMIT;

-- Officers (30 spread across states and departments)
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Rajendra Kumar Sharma','EMP001',1,'District Agriculture Officer','Lucknow','Uttar Pradesh','9415001111',DATE '2010-06-15');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Sunita Devi Yadav','EMP002',2,'Block Development Officer','Varanasi','Uttar Pradesh','9415002222',DATE '2012-03-20');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Amarjit Singh Gill','EMP003',3,'District Health Officer','Ludhiana','Punjab','9814003333',DATE '2008-09-01');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Priya Ramesh Nair','EMP004',4,'Programme Officer MGNREGS','Patna','Bihar','7234004444',DATE '2015-01-10');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Mohan Lal Verma','EMP005',1,'Agriculture Extension Officer','Jaipur','Rajasthan','9928005555',DATE '2011-07-22');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Fatima Begum Khan','EMP006',5,'Child Development Project Officer','Bhopal','Madhya Pradesh','9301006666',DATE '2013-04-05');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Venkatesh Subramaniam','EMP007',7,'Solar Energy Manager','Chennai','Tamil Nadu','9445007777',DATE '2016-08-18');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Kavita Arun Patil','EMP008',2,'Housing Welfare Officer','Pune','Maharashtra','9423008888',DATE '2014-11-30');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Suresh Chandra Meena','EMP009',6,'Social Welfare Officer','Ajmer','Rajasthan','9928009999',DATE '2009-05-12');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Anitha Krishnaswamy','EMP010',3,'Primary Health Officer','Coimbatore','Tamil Nadu','9445010000',DATE '2017-02-28');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Gurpreet Singh Bhatia','EMP011',4,'Block Level Facilitator','Amritsar','Punjab','9814011111',DATE '2010-10-10');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Dinesh Prasad Dubey','EMP012',1,'Senior Agriculture Officer','Gorakhpur','Uttar Pradesh','9415012222',DATE '2007-03-15');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Meena Ravi Kumar','EMP013',5,'District Women Welfare Officer','Hyderabad','Telangana','9040013333',DATE '2012-09-25');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Bikram Jit Mahato','EMP014',4,'MGNREGS Programme Officer','Ranchi','Jharkhand','7004014444',DATE '2014-04-01');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Sarita Bhatt','EMP015',3,'Block Medical Officer','Dehradun','Uttarakhand','9456015555',DATE '2016-12-10');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Ramesh Narayan Pillai','EMP016',2,'Urban Housing Officer','Thiruvananthapuram','Kerala','9744016666',DATE '2011-07-04');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Lakshmi Bai Sahu','EMP017',6,'Tribal Welfare Officer','Raipur','Chhattisgarh','7049017777',DATE '2013-08-20');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Arjun Dev Thakur','EMP018',7,'Renewable Energy Officer','Shimla','Himachal Pradesh','9816018888',DATE '2019-01-15');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Parveen Akhtar','EMP019',4,'Rural Development Officer','Guwahati','Assam','9435019999',DATE '2015-03-22');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Sukhdev Singh Sandhu','EMP020',1,'Kisan Seva Kendra Manager','Bathinda','Punjab','9814020000',DATE '2008-11-11');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Geeta Rani Mishra','EMP021',5,'Anganwadi Supervisor','Prayagraj','Uttar Pradesh','9415021111',DATE '2010-05-30');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Md Iqbal Hussain','EMP022',3,'District Immunisation Officer','Muzaffarpur','Bihar','7234022222',DATE '2013-02-14');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Devika Shankar Rao','EMP023',6,'SC ST Development Officer','Vijayawada','Andhra Pradesh','8332023333',DATE '2017-07-01');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Harcharan Singh Mann','EMP024',1,'Agriculture Technology Manager','Patiala','Punjab','9814024444',DATE '2009-04-06');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Rekha Jha','EMP025',4,'Block Programme Manager','Darbhanga','Bihar','7234025555',DATE '2016-09-18');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Anil Shankar Tiwari','EMP026',2,'Pradhan Mantri Awas Officer','Agra','Uttar Pradesh','9415026666',DATE '2012-01-25');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Manjula Devi Nair','EMP027',5,'Child Welfare Officer','Kozhikode','Kerala','9744027777',DATE '2018-03-08');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Prakash Rao Desai','EMP028',7,'Solar Mission Coordinator','Gandhinagar','Gujarat','9979028888',DATE '2020-05-01');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Champa Bai Rawat','EMP029',6,'Divyang Welfare Coordinator','Indore','Madhya Pradesh','9301029999',DATE '2015-11-20');
INSERT INTO Officer (officer_name, employee_code, department_id, designation, assigned_district, assigned_state, phone, join_date)
VALUES ('Nandita Ghosh','EMP030',3,'Health Programme Officer','Kolkata','West Bengal','9831030000',DATE '2014-06-12');

COMMIT;


-- ============================================================
--  PART 3 — VIEWS
-- ============================================================

-- application pipeline — good for officer dashboards
CREATE OR REPLACE VIEW V_APPLICATION_PIPELINE AS
SELECT
    a.application_id,
    c.full_name,
    c.aadhaar_number,
    c.state,
    c.district,
    c.category,
    c.annual_income,
    s.scheme_name,
    s.scheme_type,
    a.status,
    a.apply_date,
    a.priority_score,
    o.officer_name,
    fd.amount AS disbursed_amount
FROM Application a
JOIN Citizen c   ON a.citizen_id = c.citizen_id
JOIN Scheme s    ON a.scheme_id  = s.scheme_id
LEFT JOIN Officer o    ON a.officer_id = o.officer_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id;

-- how much of each scheme budget has been used
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

-- officer-level summary view
CREATE OR REPLACE VIEW V_OFFICER_PERFORMANCE AS
SELECT
    o.officer_id,
    o.officer_name,
    o.assigned_state,
    d.department_name,
    COUNT(a.application_id) AS total_handled,
    SUM(CASE WHEN a.status = 'APPROVED'  THEN 1 ELSE 0 END) AS approved,
    SUM(CASE WHEN a.status = 'REJECTED'  THEN 1 ELSE 0 END) AS rejected,
    SUM(CASE WHEN a.status = 'DISBURSED' THEN 1 ELSE 0 END) AS disbursed,
    ROUND(AVG(CASE WHEN a.approval_date IS NOT NULL
              THEN a.approval_date - a.apply_date END), 1) AS avg_days
FROM Officer o
JOIN Department d ON o.department_id = d.department_id
LEFT JOIN Application a ON o.officer_id = a.officer_id
GROUP BY o.officer_id, o.officer_name, o.assigned_state, d.department_name;


-- ============================================================
--  PART 4 — PL/SQL FUNCTIONS
-- ============================================================

-- FUNCTION 1: check_eligibility
-- returns ELIGIBLE or a reason why not
-- checks income, age, category, location against the rule table
CREATE OR REPLACE FUNCTION check_eligibility(
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER
) RETURN VARCHAR2 AS

    v_age       NUMBER;
    v_income    NUMBER;
    v_category  VARCHAR2(5);
    v_location  VARCHAR2(10);
    v_gender    CHAR(1);
    v_land      NUMBER;
    v_active    CHAR(1);

    v_min_age   NUMBER;
    v_max_age   NUMBER;
    v_max_inc   NUMBER;
    v_min_inc   NUMBER;
    v_cats      VARCHAR2(50);
    v_loc_req   VARCHAR2(10);
    v_gen_req   VARCHAR2(5);
    v_min_land  NUMBER;

BEGIN
    -- is the scheme even running
    SELECT is_active INTO v_active FROM Scheme WHERE scheme_id = p_scheme_id;
    IF v_active = 'N' THEN
        RETURN 'INELIGIBLE: Scheme is currently inactive';
    END IF;

    -- grab citizen profile
    SELECT age, annual_income, category, location_type, gender, land_holding_acres
    INTO v_age, v_income, v_category, v_location, v_gender, v_land
    FROM Citizen WHERE citizen_id = p_citizen_id;

    -- grab the eligibility rules for this scheme
    SELECT min_age, max_age, max_income, min_income,
           allowed_categories, location_type, gender_restriction, min_land_acres
    INTO v_min_age, v_max_age, v_max_inc, v_min_inc,
         v_cats, v_loc_req, v_gen_req, v_min_land
    FROM Scheme_Eligibility_Rules WHERE scheme_id = p_scheme_id;

    -- age check
    IF v_age < v_min_age OR v_age > v_max_age THEN
        RETURN 'INELIGIBLE: Age ' || v_age || ' out of range [' || v_min_age || '-' || v_max_age || ']';
    END IF;

    -- income upper limit
    IF v_max_inc IS NOT NULL AND v_income > v_max_inc THEN
        RETURN 'INELIGIBLE: Income Rs.' || v_income || ' exceeds limit of Rs.' || v_max_inc;
    END IF;

    -- income lower limit (for solar scheme)
    IF v_income < v_min_inc THEN
        RETURN 'INELIGIBLE: Income Rs.' || v_income || ' below minimum Rs.' || v_min_inc;
    END IF;

    -- category check
    IF v_cats != 'ALL' AND INSTR(v_cats, v_category) = 0 THEN
        RETURN 'INELIGIBLE: Category ' || v_category || ' not allowed. Eligible: ' || v_cats;
    END IF;

    -- location check
    IF v_loc_req != 'ALL' AND v_location != v_loc_req THEN
        RETURN 'INELIGIBLE: Scheme requires ' || v_loc_req || ' residents';
    END IF;

    -- gender check
    IF v_gen_req != 'ALL' AND v_gender != v_gen_req THEN
        RETURN 'INELIGIBLE: Scheme is gender restricted';
    END IF;

    -- land check for farmer schemes
    IF v_min_land > 0 AND v_land < v_min_land THEN
        RETURN 'INELIGIBLE: Land ' || v_land || ' acres below minimum ' || v_min_land;
    END IF;

    RETURN 'ELIGIBLE';

EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 'INELIGIBLE: Data not found';
    WHEN OTHERS THEN RETURN 'ERROR: ' || SQLERRM;
END check_eligibility;
/

-- FUNCTION 2: calculate_benefit
-- not a flat amount — varies by income, category, age
-- lower income + SC/ST + rural + elderly = higher benefit
CREATE OR REPLACE FUNCTION calculate_benefit(
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER
) RETURN NUMBER AS

    v_base      NUMBER;
    v_max       NUMBER;
    v_income    NUMBER;
    v_category  VARCHAR2(5);
    v_location  VARCHAR2(10);
    v_age       NUMBER;
    v_benefit   NUMBER;
    v_factor    NUMBER;

BEGIN
    SELECT base_benefit_amount, max_benefit_amount
    INTO v_base, v_max
    FROM Scheme WHERE scheme_id = p_scheme_id;

    SELECT annual_income, category, location_type, age
    INTO v_income, v_category, v_location, v_age
    FROM Citizen WHERE citizen_id = p_citizen_id;

    -- income-based scaling — poorer citizens get closer to base
    IF v_income <= 50000 THEN
        v_factor := 1.0;
    ELSIF v_income <= 150000 THEN
        v_factor := 0.88;
    ELSIF v_income <= 300000 THEN
        v_factor := 0.75;
    ELSIF v_income <= 500000 THEN
        v_factor := 0.60;
    ELSE
        v_factor := 0.40;
    END IF;

    v_benefit := v_base * v_factor;

    -- SC/ST get extra support as per policy
    IF v_category IN ('SC', 'ST') THEN
        v_benefit := v_benefit * 1.20;
    ELSIF v_category = 'OBC' THEN
        v_benefit := v_benefit * 1.10;
    END IF;

    -- rural bonus
    IF v_location = 'RURAL' THEN
        v_benefit := v_benefit * 1.08;
    END IF;

    -- elderly bonus
    IF v_age >= 60 THEN
        v_benefit := v_benefit * 1.12;
    END IF;

    -- cap it
    IF v_benefit > v_max THEN
        v_benefit := v_max;
    END IF;

    RETURN ROUND(v_benefit, 2);

EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
    WHEN OTHERS THEN RETURN -1;
END calculate_benefit;
/

-- FUNCTION 3: get_priority_score
-- gives a score out of 100 so officers can sort their queue
-- income matters most (50 pts), then category, location, age
CREATE OR REPLACE FUNCTION get_priority_score(
    p_citizen_id IN NUMBER
) RETURN NUMBER AS

    v_income   NUMBER;
    v_category VARCHAR2(5);
    v_location VARCHAR2(10);
    v_age      NUMBER;
    v_score    NUMBER := 0;

BEGIN
    SELECT annual_income, category, location_type, age
    INTO v_income, v_category, v_location, v_age
    FROM Citizen WHERE citizen_id = p_citizen_id;

    -- income: max 50 points, inverse relation
    IF v_income <= 50000 THEN      v_score := v_score + 50;
    ELSIF v_income <= 100000 THEN  v_score := v_score + 44;
    ELSIF v_income <= 200000 THEN  v_score := v_score + 36;
    ELSIF v_income <= 350000 THEN  v_score := v_score + 26;
    ELSIF v_income <= 500000 THEN  v_score := v_score + 16;
    ELSE                           v_score := v_score + 5;
    END IF;

    -- category: 25 points max
    IF v_category = 'ST'  THEN v_score := v_score + 25;
    ELSIF v_category = 'SC'  THEN v_score := v_score + 22;
    ELSIF v_category = 'OBC' THEN v_score := v_score + 14;
    ELSE                          v_score := v_score + 5;
    END IF;

    -- location: 15 points
    IF v_location = 'RURAL' THEN v_score := v_score + 15;
    ELSE                         v_score := v_score + 5;
    END IF;

    -- age 60+: extra 10 points
    IF v_age >= 60 THEN v_score := v_score + 10;
    END IF;

    RETURN v_score;

EXCEPTION
    WHEN OTHERS THEN RETURN 0;
END get_priority_score;
/

-- FUNCTION 4: is_duplicate_app
-- quick check before inserting a new application
CREATE OR REPLACE FUNCTION is_duplicate_app(
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
END is_duplicate_app;
/

-- FUNCTION 5: get_scheme_utilization
-- what % of the budget has been spent for a scheme
CREATE OR REPLACE FUNCTION get_scheme_utilization(
    p_scheme_id IN NUMBER
) RETURN NUMBER AS
    v_total  NUMBER;
    v_spent  NUMBER;
BEGIN
    SELECT total_budget, disbursed_amount
    INTO v_total, v_spent
    FROM Scheme_Fund_Pool WHERE scheme_id = p_scheme_id;

    IF v_total = 0 THEN RETURN 0; END IF;
    RETURN ROUND((v_spent / v_total) * 100, 2);
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
END get_scheme_utilization;
/


-- ============================================================
--  PART 5 — STORED PROCEDURES
-- ============================================================

-- PROCEDURE 1: generate_citizen_data
-- creates ~1000 realistic citizens using PL/SQL loops + DBMS_RANDOM
-- names are hand-picked to feel real, not algorithmically generated
CREATE OR REPLACE PROCEDURE generate_citizen_data AS

    -- male first names — mix of north, south, east India
    TYPE str_arr IS TABLE OF VARCHAR2(60);

    v_male_names str_arr := str_arr(
        'Rajesh','Suresh','Dinesh','Ramesh','Mahesh','Naresh','Umesh',
        'Arjun','Devendra','Pradeep','Santosh','Harish','Manish','Anil',
        'Vijay','Ajay','Sanjay','Ranjit','Gurpreet','Amarjit','Harpreet',
        'Mohammad','Imran','Farhan','Salman','Irfan','Riyaz',
        'Venkatesh','Krishnaswamy','Ramamurthy','Balakrishnan','Subramaniam',
        'Bikash','Debashish','Partha','Sourav','Prasanta',
        'Rohit','Amit','Vikas','Ashok','Pramod','Hemant','Deepak',
        'Shyam','Govind','Brijesh','Yogendra','Virendra','Satendra',
        'Ramakant','Shivaji','Kuldeep','Jaswant','Baldev'
    );

    v_female_names str_arr := str_arr(
        'Sunita','Anita','Kavita','Savita','Sangita','Mamta','Seema','Geeta',
        'Rekha','Usha','Meena','Asha','Nisha','Lata','Sita','Manju',
        'Gurpreet','Manpreet','Simranjit','Paramjit','Harpreet',
        'Fatima','Aisha','Rukhsar','Shabana','Nasreen','Yasmin',
        'Lakshmi','Saraswati','Kamala','Radha','Meenakshi','Vijayalakshmi',
        'Sudha','Rohini','Sushma','Shanta','Vimala','Jayashree',
        'Champa','Pushpa','Kusum','Madhuri','Vandana','Archana','Swati',
        'Priya','Pooja','Neha','Divya','Deepa','Ritu','Saroj','Geeta'
    );

    v_surnames str_arr := str_arr(
        'Sharma','Verma','Gupta','Singh','Kumar','Yadav','Patel','Shah',
        'Joshi','Mishra','Tiwari','Dubey','Pandey','Shukla','Srivastava',
        'Rao','Reddy','Naidu','Iyer','Pillai','Nair','Menon','Krishnan',
        'Das','Dutta','Ghosh','Banerjee','Chatterjee','Mukherjee',
        'Gill','Sidhu','Mann','Grewal','Dhillon','Sandhu','Chahal',
        'Khan','Ansari','Shaikh','Qureshi','Siddiqui','Malik','Chaudhary',
        'Meena','Bhil','Gond','Munda','Lodhi','Mahato','Sahu','Thakur',
        'Rawat','Bisht','Negi','Chauhan','Rathore','Desai','Mehta',
        'Jadhav','Patil','More','Shinde','Kamble','Pawar','Bhosale',
        'Naik','Gawade','Sawant','Chavan','Deshpande','Kulkarni','Jain'
    );

    -- states weighted by population — UP appears 17 times, MH 9, etc.
    v_states str_arr := str_arr(
        'Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh',
        'Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh',
        'Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh','Uttar Pradesh',
        'Uttar Pradesh','Uttar Pradesh',
        'Maharashtra','Maharashtra','Maharashtra','Maharashtra','Maharashtra',
        'Maharashtra','Maharashtra','Maharashtra','Maharashtra',
        'Bihar','Bihar','Bihar','Bihar','Bihar','Bihar','Bihar','Bihar','Bihar',
        'West Bengal','West Bengal','West Bengal','West Bengal','West Bengal',
        'West Bengal','West Bengal','West Bengal',
        'Madhya Pradesh','Madhya Pradesh','Madhya Pradesh','Madhya Pradesh','Madhya Pradesh',
        'Rajasthan','Rajasthan','Rajasthan','Rajasthan','Rajasthan',
        'Tamil Nadu','Tamil Nadu','Tamil Nadu','Tamil Nadu',
        'Karnataka','Karnataka','Karnataka',
        'Gujarat','Gujarat','Gujarat',
        'Andhra Pradesh','Andhra Pradesh',
        'Odisha','Odisha',
        'Telangana','Telangana',
        'Punjab','Punjab',
        'Jharkhand',
        'Chhattisgarh',
        'Assam',
        'Haryana',
        'Kerala',
        'Uttarakhand'
    );

    v_districts str_arr := str_arr(
        'Lucknow','Varanasi','Agra','Kanpur','Prayagraj','Gorakhpur','Meerut',
        'Bareilly','Aligarh','Moradabad','Mathura','Jhansi','Ghaziabad',
        'Saharanpur','Muzaffarnagar','Firozabad','Etawah',
        'Pune','Mumbai','Nagpur','Nashik','Aurangabad','Kolhapur','Solapur','Amravati','Latur',
        'Patna','Gaya','Muzaffarpur','Darbhanga','Bhagalpur','Purnia','Arrah','Begusarai','Nalanda',
        'Kolkata','Howrah','Burdwan','Murshidabad','Nadia','Malda','Jalpaiguri','Midnapore',
        'Bhopal','Indore','Gwalior','Jabalpur','Sagar',
        'Jaipur','Jodhpur','Udaipur','Ajmer','Bikaner',
        'Chennai','Coimbatore','Madurai','Salem',
        'Bengaluru','Mysuru','Hubballi',
        'Ahmedabad','Surat','Vadodara',
        'Visakhapatnam','Vijayawada',
        'Bhubaneswar','Cuttack',
        'Hyderabad','Warangal',
        'Ludhiana','Amritsar',
        'Ranchi',
        'Raipur',
        'Guwahati',
        'Gurugram',
        'Thiruvananthapuram',
        'Dehradun'
    );

    -- category distribution: SC~17, ST~8, OBC~40, GEN~35
    v_categories str_arr := str_arr(
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

    v_occupations str_arr := str_arr(
        'Farmer','Farmer','Farmer','Farmer','Agricultural Labourer','Agricultural Labourer',
        'Daily Wage Labourer','Daily Wage Labourer','Construction Worker',
        'Small Trader','Shopkeeper','Hawker','Tailor','Weaver',
        'Government Employee','Private Sector Employee',
        'Self Employed','Artisan','Potter','Driver','Mechanic',
        'Teacher','Health Worker','ASHA Worker',
        'Student','Unemployed','Retired','Domestic Worker'
    );

    v_ifsc_codes str_arr := str_arr(
        'SBIN0001234','SBIN0005678','PUNB0012300','PUNB0056700',
        'UBIN0012345','BKID0001234','CNRB0001234','HDFC0001234',
        'ICIC0001234','BARB0001234','MAHB0001234','IOBA0001234'
    );

    -- working variables
    v_gender     CHAR(1);
    v_fname      VARCHAR2(60);
    v_sname      VARCHAR2(60);
    v_fullname   VARCHAR2(100);
    v_age        NUMBER;
    v_dob        DATE;
    v_category   VARCHAR2(5);
    v_income     NUMBER;
    v_location   VARCHAR2(10);
    v_state      VARCHAR2(100);
    v_district   VARCHAR2(100);
    v_village    VARCHAR2(100);
    v_occupation VARCHAR2(100);
    v_land       NUMBER;
    v_pincode    VARCHAR2(6);
    v_bank       VARCHAR2(20);
    v_ifsc       VARCHAR2(11);
    v_aadhaar    VARCHAR2(12);
    v_rand       NUMBER;
    v_state_idx  NUMBER;
    v_inc_rand   NUMBER;

BEGIN
    DBMS_OUTPUT.PUT_LINE('Generating citizen data...');

    FOR i IN 1..1000 LOOP

        -- gender: roughly 51.5% male
        IF DBMS_RANDOM.VALUE(0,100) <= 51.5 THEN
            v_gender := 'M';
            v_fname  := v_male_names(ROUND(DBMS_RANDOM.VALUE(1, v_male_names.COUNT)));
        ELSE
            v_gender := 'F';
            v_fname  := v_female_names(ROUND(DBMS_RANDOM.VALUE(1, v_female_names.COUNT)));
        END IF;

        v_sname    := v_surnames(ROUND(DBMS_RANDOM.VALUE(1, v_surnames.COUNT)));
        v_fullname := v_fname || ' ' || v_sname;

        -- age distribution: 45% young (18-35), 35% mid (36-55), 20% senior (56-75)
        v_rand := DBMS_RANDOM.VALUE(0,100);
        IF v_rand <= 45 THEN
            v_age := ROUND(DBMS_RANDOM.VALUE(18, 35));
        ELSIF v_rand <= 80 THEN
            v_age := ROUND(DBMS_RANDOM.VALUE(36, 55));
        ELSE
            v_age := ROUND(DBMS_RANDOM.VALUE(56, 75));
        END IF;
        v_dob := ADD_MONTHS(SYSDATE, -(v_age * 12));

        v_category := v_categories(ROUND(DBMS_RANDOM.VALUE(1, v_categories.COUNT)));

        -- state + district (weighted by population)
        v_state_idx := ROUND(DBMS_RANDOM.VALUE(1, v_states.COUNT));
        v_state     := v_states(v_state_idx);
        v_district  := v_districts(LEAST(v_state_idx, v_districts.COUNT));

        -- 65% rural (Census 2011)
        IF DBMS_RANDOM.VALUE(0,100) <= 65 THEN
            v_location := 'RURAL';
            v_village  := 'Village-' || ROUND(DBMS_RANDOM.VALUE(1,999));
        ELSE
            v_location := 'URBAN';
            v_village  := v_district;
        END IF;

        -- income: right-skewed like actual India (40% very poor, 30% low, etc.)
        v_inc_rand := DBMS_RANDOM.VALUE(0,100);
        IF v_inc_rand <= 40 THEN
            v_income := ROUND(DBMS_RANDOM.VALUE(20000, 100000), -2);
        ELSIF v_inc_rand <= 70 THEN
            v_income := ROUND(DBMS_RANDOM.VALUE(100000, 250000), -2);
        ELSIF v_inc_rand <= 85 THEN
            v_income := ROUND(DBMS_RANDOM.VALUE(250000, 500000), -2);
        ELSIF v_inc_rand <= 95 THEN
            v_income := ROUND(DBMS_RANDOM.VALUE(500000, 1000000), -2);
        ELSE
            v_income := ROUND(DBMS_RANDOM.VALUE(1000000, 3000000), -2);
        END IF;

        v_occupation := v_occupations(ROUND(DBMS_RANDOM.VALUE(1, v_occupations.COUNT)));

        IF v_occupation IN ('Farmer','Agricultural Labourer') THEN
            v_land := ROUND(DBMS_RANDOM.VALUE(0.5, 8), 1);
        ELSE
            v_land := 0;
        END IF;

        v_pincode  := LPAD(TO_CHAR(ROUND(DBMS_RANDOM.VALUE(110001, 799999))), 6, '0');
        v_bank     := 'ACCT' || LPAD(TO_CHAR(i), 12, '0');
        v_ifsc     := v_ifsc_codes(ROUND(DBMS_RANDOM.VALUE(1, v_ifsc_codes.COUNT)));
        v_aadhaar  := LPAD(TO_CHAR(700000000000 + i), 12, '0');

        INSERT INTO Citizen (
            aadhaar_number, full_name, gender, date_of_birth, age,
            category, annual_income, occupation, land_holding_acres,
            location_type, village_town, district, state, pincode,
            bank_account, ifsc_code, is_verified, registration_date
        ) VALUES (
            v_aadhaar, v_fullname, v_gender, v_dob, v_age,
            v_category, v_income, v_occupation, v_land,
            v_location, v_village, v_district, v_state, v_pincode,
            v_bank, v_ifsc,
            CASE WHEN DBMS_RANDOM.VALUE(0,1) > 0.3 THEN 'Y' ELSE 'N' END,
            SYSDATE - ROUND(DBMS_RANDOM.VALUE(0,365))
        );

        IF MOD(i, 100) = 0 THEN
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('  Inserted ' || i || ' citizens...');
        END IF;

    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Done. 1000 citizens generated.');

EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('Duplicate found — rolling back');
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END generate_citizen_data;
/

-- run it
BEGIN generate_citizen_data; END;
/


-- PROCEDURE 2: generate_sample_applications
-- uses cursors to loop through eligible citizen groups
-- and create applications for relevant schemes
CREATE OR REPLACE PROCEDURE generate_sample_applications AS

    -- farmers for Kisan Samman Yojana
    CURSOR c_farmers IS
        SELECT citizen_id, annual_income, category, location_type
        FROM Citizen
        WHERE occupation IN ('Farmer','Agricultural Labourer')
          AND land_holding_acres BETWEEN 0.1 AND 5
          AND annual_income < 250000
          AND ROWNUM <= 200;

    -- rural BPL for Gramin Awas
    CURSOR c_bpl_rural IS
        SELECT citizen_id, annual_income, category
        FROM Citizen
        WHERE annual_income < 100000
          AND location_type = 'RURAL'
          AND ROWNUM <= 150;

    -- broad low income for health scheme
    CURSOR c_health IS
        SELECT citizen_id
        FROM Citizen
        WHERE annual_income < 500000
          AND ROWNUM <= 250;

    v_officer_id NUMBER;
    v_status     VARCHAR2(20);
    v_score      NUMBER;
    v_app_date   DATE;

    -- status distribution to make it realistic
    TYPE status_list IS TABLE OF VARCHAR2(20);
    v_statuses status_list := status_list(
        'SUBMITTED','SUBMITTED','UNDER_REVIEW',
        'APPROVED','APPROVED','REJECTED','DISBURSED'
    );

BEGIN
    -- Kisan Samman applications
    FOR r IN c_farmers LOOP
        BEGIN
            v_officer_id := ROUND(DBMS_RANDOM.VALUE(1, 5));
            v_status     := v_statuses(ROUND(DBMS_RANDOM.VALUE(1, 7)));
            v_app_date   := SYSDATE - ROUND(DBMS_RANDOM.VALUE(10, 180));
            v_score      := get_priority_score(r.citizen_id);

            INSERT INTO Application (
                citizen_id, scheme_id, officer_id, apply_date,
                status, priority_score, approval_date
            ) VALUES (
                r.citizen_id, 1, v_officer_id, v_app_date,
                v_status, v_score,
                CASE WHEN v_status IN ('APPROVED','DISBURSED')
                     THEN v_app_date + ROUND(DBMS_RANDOM.VALUE(5,30))
                     ELSE NULL END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
    END LOOP;

    -- Gramin Awas applications
    FOR r IN c_bpl_rural LOOP
        BEGIN
            v_officer_id := ROUND(DBMS_RANDOM.VALUE(2, 8));
            v_status     := v_statuses(ROUND(DBMS_RANDOM.VALUE(1, 7)));
            v_app_date   := SYSDATE - ROUND(DBMS_RANDOM.VALUE(10, 180));
            v_score      := get_priority_score(r.citizen_id);

            INSERT INTO Application (
                citizen_id, scheme_id, officer_id, apply_date,
                status, priority_score, approval_date
            ) VALUES (
                r.citizen_id, 2, v_officer_id, v_app_date,
                v_status, v_score,
                CASE WHEN v_status IN ('APPROVED','DISBURSED')
                     THEN v_app_date + ROUND(DBMS_RANDOM.VALUE(7,45))
                     ELSE NULL END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
    END LOOP;

    -- Swasthya Suraksha applications
    FOR r IN c_health LOOP
        BEGIN
            v_officer_id := ROUND(DBMS_RANDOM.VALUE(3, 15));
            v_status     := v_statuses(ROUND(DBMS_RANDOM.VALUE(1, 7)));
            v_app_date   := SYSDATE - ROUND(DBMS_RANDOM.VALUE(5, 200));
            v_score      := get_priority_score(r.citizen_id);

            INSERT INTO Application (
                citizen_id, scheme_id, officer_id, apply_date,
                status, priority_score, approval_date
            ) VALUES (
                r.citizen_id, 3, v_officer_id, v_app_date,
                v_status, v_score,
                CASE WHEN v_status IN ('APPROVED','DISBURSED')
                     THEN v_app_date + ROUND(DBMS_RANDOM.VALUE(3,25))
                     ELSE NULL END
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Sample applications generated.');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END generate_sample_applications;
/

BEGIN generate_sample_applications; END;
/

-- generate disbursement records for approved/disbursed apps
INSERT INTO Fund_Disbursement (
    application_id, amount, disbursement_date,
    payment_mode, transaction_ref, bank_account, status
)
SELECT
    a.application_id,
    calculate_benefit(a.citizen_id, a.scheme_id),
    a.approval_date + ROUND(DBMS_RANDOM.VALUE(1,7)),
    'DBT',
    'TXN' || TO_CHAR(SYSDATE,'YYYYMMDD') || LPAD(a.application_id, 8,'0'),
    c.bank_account,
    'PROCESSED'
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
WHERE a.status IN ('APPROVED','DISBURSED')
  AND NOT EXISTS (
      SELECT 1 FROM Fund_Disbursement fd WHERE fd.application_id = a.application_id
  );

-- update fund pools to reflect disbursements
UPDATE Scheme_Fund_Pool sfp
SET disbursed_amount = (
    SELECT NVL(SUM(fd.amount), 0)
    FROM Fund_Disbursement fd
    JOIN Application a ON fd.application_id = a.application_id
    WHERE a.scheme_id = sfp.scheme_id AND fd.status = 'PROCESSED'
),
last_updated = SYSDATE;

COMMIT;


-- PROCEDURE 3: apply_scheme
-- the main application submission procedure
-- validates, checks duplicate, scores, inserts
CREATE OR REPLACE PROCEDURE apply_scheme(
    p_citizen_id IN NUMBER,
    p_scheme_id  IN NUMBER,
    p_remarks    IN VARCHAR2 DEFAULT NULL
) AS
    v_eligible   VARCHAR2(200);
    v_duplicate  CHAR(1);
    v_score      NUMBER;
    v_cname      VARCHAR2(100);
    v_sname      VARCHAR2(150);

BEGIN
    -- basic existence checks
    BEGIN
        SELECT full_name INTO v_cname FROM Citizen WHERE citizen_id = p_citizen_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Citizen ID ' || p_citizen_id || ' does not exist');
    END;

    BEGIN
        SELECT scheme_name INTO v_sname
        FROM Scheme WHERE scheme_id = p_scheme_id AND is_active = 'Y';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'Scheme not found or inactive');
    END;

    -- duplicate check
    v_duplicate := is_duplicate_app(p_citizen_id, p_scheme_id);
    IF v_duplicate = 'Y' THEN
        RAISE_APPLICATION_ERROR(-20003,
            v_cname || ' already has an active application for ' || v_sname);
    END IF;

    -- eligibility
    v_eligible := check_eligibility(p_citizen_id, p_scheme_id);

    -- score
    v_score := get_priority_score(p_citizen_id);

    -- insert the application
    INSERT INTO Application (
        citizen_id, scheme_id, apply_date, status, priority_score, remarks
    ) VALUES (
        p_citizen_id, p_scheme_id, SYSDATE, 'SUBMITTED', v_score,
        NVL(p_remarks, 'Self-applied')
    );

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Application submitted for: ' || v_cname);
    DBMS_OUTPUT.PUT_LINE('Scheme: ' || v_sname);
    DBMS_OUTPUT.PUT_LINE('Priority Score: ' || v_score);
    DBMS_OUTPUT.PUT_LINE('Eligibility Check: ' || v_eligible);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
END apply_scheme;
/


-- PROCEDURE 4: approve_application
-- officer approves or rejects, triggers disbursement if approved
CREATE OR REPLACE PROCEDURE approve_application(
    p_app_id    IN NUMBER,
    p_officer_id IN NUMBER,
    p_action    IN VARCHAR2,
    p_remarks   IN VARCHAR2 DEFAULT NULL
) AS
    v_citizen_id NUMBER;
    v_scheme_id  NUMBER;
    v_curr_status VARCHAR2(20);
    v_benefit    NUMBER;
    v_bank       VARCHAR2(20);
    v_txn        VARCHAR2(50);
    v_fund_left  NUMBER;

BEGIN
    -- lock and fetch the application
    SELECT citizen_id, scheme_id, status
    INTO v_citizen_id, v_scheme_id, v_curr_status
    FROM Application
    WHERE application_id = p_app_id
    FOR UPDATE;

    IF v_curr_status NOT IN ('SUBMITTED','UNDER_REVIEW') THEN
        RAISE_APPLICATION_ERROR(-20010,
            'Application already processed. Status: ' || v_curr_status);
    END IF;

    -- assign officer
    UPDATE Application SET officer_id = p_officer_id WHERE application_id = p_app_id;

    IF UPPER(p_action) = 'APPROVE' THEN

        -- check fund availability
        SELECT total_budget - disbursed_amount INTO v_fund_left
        FROM Scheme_Fund_Pool WHERE scheme_id = v_scheme_id;

        v_benefit := calculate_benefit(v_citizen_id, v_scheme_id);

        IF v_fund_left < v_benefit THEN
            RAISE_APPLICATION_ERROR(-20011, 'Insufficient funds in scheme pool');
        END IF;

        -- approve it
        UPDATE Application
        SET status = 'APPROVED',
            approval_date = SYSDATE,
            remarks = NVL(p_remarks, remarks)
        WHERE application_id = p_app_id;

        -- create disbursement
        SELECT bank_account INTO v_bank FROM Citizen WHERE citizen_id = v_citizen_id;
        v_txn := 'TXN' || TO_CHAR(SYSDATE,'YYYYMMDD') || LPAD(p_app_id, 8,'0');

        INSERT INTO Fund_Disbursement (
            application_id, amount, disbursement_date,
            payment_mode, transaction_ref, bank_account, status
        ) VALUES (
            p_app_id, v_benefit, SYSDATE, 'DBT', v_txn, v_bank, 'PROCESSED'
        );

        -- update fund pool
        UPDATE Scheme_Fund_Pool
        SET disbursed_amount = disbursed_amount + v_benefit,
            last_updated = SYSDATE
        WHERE scheme_id = v_scheme_id;

        -- mark disbursed
        UPDATE Application SET status = 'DISBURSED' WHERE application_id = p_app_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Approved and disbursed Rs.' || v_benefit);
        DBMS_OUTPUT.PUT_LINE('Transaction: ' || v_txn);

    ELSIF UPPER(p_action) = 'REJECT' THEN
        UPDATE Application
        SET status = 'REJECTED',
            rejection_reason = NVL(p_remarks, 'Rejected during review'),
            approval_date = SYSDATE
        WHERE application_id = p_app_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Application ' || p_app_id || ' rejected.');

    ELSE
        RAISE_APPLICATION_ERROR(-20012, 'Invalid action. Use APPROVE or REJECT');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        RAISE;
END approve_application;
/


-- PROCEDURE 5: generate_scheme_report
-- cursor-based report: prints scheme stats to DBMS_OUTPUT
CREATE OR REPLACE PROCEDURE generate_scheme_report AS

    CURSOR c_report IS
        SELECT
            s.scheme_name,
            s.scheme_type,
            sfp.total_budget,
            sfp.disbursed_amount,
            sfp.total_budget - sfp.disbursed_amount AS remaining,
            COUNT(a.application_id) AS total_apps,
            SUM(CASE WHEN a.status = 'DISBURSED' THEN 1 ELSE 0 END) AS done,
            SUM(CASE WHEN a.status IN ('SUBMITTED','UNDER_REVIEW') THEN 1 ELSE 0 END) AS pending
        FROM Scheme s
        JOIN Scheme_Fund_Pool sfp ON s.scheme_id = sfp.scheme_id
        LEFT JOIN Application a ON s.scheme_id = a.scheme_id
        GROUP BY s.scheme_name, s.scheme_type, sfp.total_budget, sfp.disbursed_amount
        ORDER BY sfp.disbursed_amount DESC;

    r           c_report%ROWTYPE;
    v_tot_bud   NUMBER := 0;
    v_tot_dis   NUMBER := 0;
    v_tot_apps  NUMBER := 0;

BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SCHEME PERFORMANCE REPORT ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('Scheme',35) || RPAD('Type',8) ||
                         RPAD('Disbursed(Cr)',14) || RPAD('Apps',6) || 'Pending');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',80,'-'));

    OPEN c_report;
    LOOP
        FETCH c_report INTO r;
        EXIT WHEN c_report%NOTFOUND;

        v_tot_bud  := v_tot_bud  + r.total_budget;
        v_tot_dis  := v_tot_dis  + r.disbursed_amount;
        v_tot_apps := v_tot_apps + r.total_apps;

        DBMS_OUTPUT.PUT_LINE(
            RPAD(SUBSTR(r.scheme_name,1,33),35) ||
            RPAD(r.scheme_type,8) ||
            RPAD(TO_CHAR(ROUND(r.disbursed_amount/10000000,2)),14) ||
            RPAD(r.total_apps,6) ||
            r.pending
        );
    END LOOP;
    CLOSE c_report;

    DBMS_OUTPUT.PUT_LINE(RPAD('-',80,'-'));
    DBMS_OUTPUT.PUT_LINE('Total Budget: Rs.' || ROUND(v_tot_bud/10000000,1) || ' Cr' ||
                         '  |  Disbursed: Rs.' || ROUND(v_tot_dis/10000000,1) || ' Cr' ||
                         '  |  Applications: ' || v_tot_apps);

EXCEPTION
    WHEN OTHERS THEN
        IF c_report%ISOPEN THEN CLOSE c_report; END IF;
        DBMS_OUTPUT.PUT_LINE('Report error: ' || SQLERRM);
END generate_scheme_report;
/


-- ============================================================
--  PART 6 — TRIGGERS (exactly 3)
-- ============================================================

-- TRIGGER 1: audit log
-- fires whenever application status changes
-- populates the audit log table automatically
CREATE OR REPLACE TRIGGER trg_application_audit
AFTER UPDATE OF status ON Application
FOR EACH ROW
BEGIN
    INSERT INTO Application_Audit_Log (
        application_id, old_status, new_status, changed_by, change_date
    ) VALUES (
        :NEW.application_id, :OLD.status, :NEW.status, USER, SYSTIMESTAMP
    );
END trg_application_audit;
/

-- TRIGGER 2: fund pool update
-- fires after a disbursement is inserted
-- updates the scheme fund pool so balance stays accurate
CREATE OR REPLACE TRIGGER trg_fund_pool_update
AFTER INSERT ON Fund_Disbursement
FOR EACH ROW
DECLARE
    v_scheme_id NUMBER;
BEGIN
    SELECT scheme_id INTO v_scheme_id
    FROM Application WHERE application_id = :NEW.application_id;

    UPDATE Scheme_Fund_Pool
    SET disbursed_amount = disbursed_amount + :NEW.amount,
        last_updated = SYSDATE
    WHERE scheme_id = v_scheme_id;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Warning: scheme not found for disbursement update');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Fund update trigger error: ' || SQLERRM);
END trg_fund_pool_update;
/

-- TRIGGER 3: duplicate prevention
-- fires before any application insert
-- gives a clear error if citizen already applied for same scheme
CREATE OR REPLACE TRIGGER trg_no_duplicate_app
BEFORE INSERT ON Application
FOR EACH ROW
DECLARE
    v_count   NUMBER;
    v_sname   VARCHAR2(150);
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM Application
    WHERE citizen_id = :NEW.citizen_id
      AND scheme_id  = :NEW.scheme_id
      AND status NOT IN ('REJECTED');

    IF v_count > 0 THEN
        SELECT scheme_name INTO v_sname FROM Scheme WHERE scheme_id = :NEW.scheme_id;
        RAISE_APPLICATION_ERROR(-20030,
            'Active application already exists for scheme: ' || v_sname);
    END IF;
END trg_no_duplicate_app;
/


-- ============================================================
--  PART 7 — DEMO FLOW (run these to demo the system)
-- ============================================================

-- Step 1: Register a new citizen
BEGIN
    INSERT INTO Citizen (
        aadhaar_number, full_name, gender, date_of_birth, age,
        category, annual_income, occupation, land_holding_acres,
        location_type, village_town, district, state, pincode,
        bank_account, ifsc_code, is_verified
    ) VALUES (
        '987654321098', 'Ramkali Devi Yadav', 'F', DATE '1978-06-15', 45,
        'OBC', 85000, 'Agricultural Labourer', 1.5,
        'RURAL', 'Rampur Khas', 'Varanasi', 'Uttar Pradesh', '221001',
        'ACCT000000009999', 'SBIN0001234', 'Y'
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Citizen registered.');
END;
/

-- Step 2: Check eligibility for a few schemes
DECLARE
    v_cid NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    DBMS_OUTPUT.PUT_LINE('--- Eligibility Check for Ramkali Devi ---');
    DBMS_OUTPUT.PUT_LINE('Kisan Samman Yojana : ' || check_eligibility(v_cid, 1));
    DBMS_OUTPUT.PUT_LINE('Gramin Awas Yojana  : ' || check_eligibility(v_cid, 2));
    DBMS_OUTPUT.PUT_LINE('Swasthya Suraksha   : ' || check_eligibility(v_cid, 3));
    DBMS_OUTPUT.PUT_LINE('Ujjwala Rasoi       : ' || check_eligibility(v_cid, 5));
    DBMS_OUTPUT.PUT_LINE('Benefit (Scheme 3)  : Rs.' || calculate_benefit(v_cid, 3));
    DBMS_OUTPUT.PUT_LINE('Priority Score      : ' || get_priority_score(v_cid));
END;
/

-- Step 3: Submit application
DECLARE
    v_cid NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    apply_scheme(v_cid, 3, 'Applying for health coverage');
END;
/

-- Step 4: Officer approves it
DECLARE
    v_app_id NUMBER;
    v_cid    NUMBER;
BEGIN
    SELECT citizen_id INTO v_cid FROM Citizen WHERE aadhaar_number = '987654321098';
    SELECT application_id INTO v_app_id
    FROM Application WHERE citizen_id = v_cid AND scheme_id = 3;
    approve_application(v_app_id, 3, 'APPROVE', 'Verified documents. Eligible.');
END;
/

-- Step 5: Run the scheme report
BEGIN generate_scheme_report; END;
/

-- Step 6: View the audit trail
SELECT * FROM Application_Audit_Log ORDER BY change_date DESC;


-- ============================================================
--  PART 8 — SQL QUERIES (12 structured queries)
-- ============================================================

-- ╔═══════════════════════════════════╗
-- ║  SECTION 1 — BASIC VALIDATION    ║
-- ╚═══════════════════════════════════╝

-- Q1: list all schemes with their department
SELECT
    s.scheme_name,
    s.scheme_type,
    d.department_name,
    s.base_benefit_amount,
    s.is_active
FROM Scheme s
JOIN Department d ON s.department_id = d.department_id
ORDER BY s.scheme_type, s.scheme_name;

-- Q2: all citizens from a specific state with their category and income
SELECT
    full_name,
    state,
    district,
    category,
    annual_income,
    location_type
FROM Citizen
WHERE state = 'Uttar Pradesh'
ORDER BY annual_income ASC;

-- Q3: applications with citizen name and scheme details
SELECT
    a.application_id,
    c.full_name,
    c.aadhaar_number,
    s.scheme_name,
    a.status,
    a.apply_date,
    a.priority_score
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
JOIN Scheme s  ON a.scheme_id  = s.scheme_id
ORDER BY a.apply_date DESC;

-- Q4: all officers with their department and assigned state
SELECT
    o.officer_name,
    o.designation,
    d.department_name,
    o.assigned_district,
    o.assigned_state
FROM Officer o
JOIN Department d ON o.department_id = d.department_id
ORDER BY o.assigned_state;


-- ╔═══════════════════════════════════╗
-- ║  SECTION 2 — BUSINESS LOGIC      ║
-- ╚═══════════════════════════════════╝

-- Q5: how many applications each scheme has, broken by status
SELECT
    s.scheme_name,
    a.status,
    COUNT(*) AS count
FROM Application a
JOIN Scheme s ON a.scheme_id = s.scheme_id
GROUP BY s.scheme_name, a.status
ORDER BY s.scheme_name, a.status;

-- Q6: citizens eligible for Swasthya Suraksha (scheme 3) who haven't applied yet
SELECT
    c.citizen_id,
    c.full_name,
    c.state,
    c.category,
    c.annual_income
FROM Citizen c
WHERE c.annual_income < 500000
  AND c.is_verified = 'Y'
  AND NOT EXISTS (
      SELECT 1 FROM Application a
      WHERE a.citizen_id = c.citizen_id AND a.scheme_id = 3
  )
ORDER BY c.annual_income ASC;

-- Q7: pending applications sorted by priority — officer's daily queue
SELECT
    a.application_id,
    c.full_name,
    c.category,
    c.annual_income,
    s.scheme_name,
    a.priority_score,
    a.apply_date,
    TRUNC(SYSDATE - a.apply_date) AS days_waiting
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
JOIN Scheme s  ON a.scheme_id  = s.scheme_id
WHERE a.status IN ('SUBMITTED','UNDER_REVIEW')
ORDER BY a.priority_score DESC, a.apply_date ASC;

-- Q8: schemes where total applications exceed 50 (popular schemes)
SELECT
    s.scheme_name,
    COUNT(a.application_id) AS total_applications
FROM Scheme s
LEFT JOIN Application a ON s.scheme_id = a.scheme_id
GROUP BY s.scheme_name
HAVING COUNT(a.application_id) > 50
ORDER BY total_applications DESC;


-- ╔══════════════════════════════════════╗
-- ║  SECTION 3 — ANALYTICS / INSIGHTS   ║
-- ╚══════════════════════════════════════╝

-- Q9: total funds disbursed per scheme
SELECT
    s.scheme_name,
    NVL(SUM(fd.amount), 0) AS total_disbursed,
    COUNT(fd.disbursement_id) AS disbursement_count,
    ROUND(NVL(AVG(fd.amount), 0), 2) AS avg_per_beneficiary
FROM Scheme s
LEFT JOIN Application a ON s.scheme_id = a.scheme_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
GROUP BY s.scheme_name
ORDER BY total_disbursed DESC;

-- Q10: scheme utilization — how much of the budget is spent
SELECT
    s.scheme_name,
    sfp.total_budget,
    sfp.disbursed_amount,
    sfp.total_budget - sfp.disbursed_amount AS remaining,
    ROUND((sfp.disbursed_amount / sfp.total_budget) * 100, 2) AS used_pct,
    CASE
        WHEN sfp.disbursed_amount / sfp.total_budget >= 0.9 THEN 'CRITICAL'
        WHEN sfp.disbursed_amount / sfp.total_budget >= 0.5 THEN 'MODERATE'
        ELSE 'HEALTHY'
    END AS budget_status
FROM Scheme s
JOIN Scheme_Fund_Pool sfp ON s.scheme_id = sfp.scheme_id
ORDER BY used_pct DESC;

-- Q11: rural vs urban beneficiary breakdown per scheme
SELECT
    s.scheme_name,
    c.location_type,
    COUNT(DISTINCT a.citizen_id) AS beneficiaries,
    NVL(SUM(fd.amount), 0) AS total_amount
FROM Scheme s
JOIN Application a ON s.scheme_id = a.scheme_id
JOIN Citizen c ON a.citizen_id = c.citizen_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
WHERE a.status IN ('APPROVED','DISBURSED')
GROUP BY s.scheme_name, c.location_type
ORDER BY s.scheme_name, c.location_type;

-- Q12: state-wise count of disbursed applications and total funds
SELECT
    c.state,
    COUNT(DISTINCT a.application_id) AS disbursed_apps,
    NVL(SUM(fd.amount), 0) AS total_funds,
    ROUND(AVG(fd.amount), 0) AS avg_benefit
FROM Citizen c
JOIN Application a ON c.citizen_id = a.citizen_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
WHERE a.status IN ('APPROVED','DISBURSED')
GROUP BY c.state
ORDER BY total_funds DESC;

-- Q13: category-wise breakdown — how many from each group got benefits
SELECT
    c.category,
    COUNT(DISTINCT c.citizen_id) AS total_citizens,
    COUNT(a.application_id) AS applications,
    SUM(CASE WHEN a.status IN ('APPROVED','DISBURSED') THEN 1 ELSE 0 END) AS approved,
    NVL(SUM(fd.amount), 0) AS total_benefit
FROM Citizen c
LEFT JOIN Application a ON c.citizen_id = a.citizen_id
LEFT JOIN Fund_Disbursement fd ON a.application_id = fd.application_id
GROUP BY c.category
ORDER BY total_benefit DESC;


-- ╔═══════════════════════════════╗
-- ║  SECTION 4 — ADVANCED        ║
-- ╚═══════════════════════════════╝

-- Q14: citizens with income below state average who haven't applied anywhere
-- useful for outreach targeting
SELECT
    c.citizen_id,
    c.full_name,
    c.state,
    c.annual_income,
    c.category
FROM Citizen c
WHERE c.annual_income < (
    SELECT AVG(annual_income) FROM Citizen c2 WHERE c2.state = c.state
)
AND NOT EXISTS (
    SELECT 1 FROM Application a WHERE a.citizen_id = c.citizen_id
)
AND c.is_verified = 'Y'
ORDER BY c.annual_income ASC;

-- Q15: fraud detection — high income citizens who applied for BPL schemes
-- income > 5L but applied to Kisan Samman or Gramin Awas
SELECT
    c.full_name,
    c.aadhaar_number,
    c.annual_income,
    c.category,
    s.scheme_name,
    a.status,
    a.apply_date
FROM Application a
JOIN Citizen c ON a.citizen_id = c.citizen_id
JOIN Scheme s  ON a.scheme_id  = s.scheme_id
WHERE c.annual_income > 500000
  AND s.scheme_id IN (1, 2, 5)
ORDER BY c.annual_income DESC;

-- Q16: officer performance — approval rate and avg processing time
SELECT
    o.officer_name,
    o.assigned_state,
    COUNT(a.application_id) AS handled,
    SUM(CASE WHEN a.status IN ('APPROVED','DISBURSED') THEN 1 ELSE 0 END) AS approved,
    SUM(CASE WHEN a.status = 'REJECTED' THEN 1 ELSE 0 END) AS rejected,
    ROUND(
        SUM(CASE WHEN a.status IN ('APPROVED','DISBURSED') THEN 1 ELSE 0 END) * 100.0
        / NULLIF(COUNT(a.application_id), 0), 1
    ) AS approval_rate_pct,
    ROUND(AVG(CASE WHEN a.approval_date IS NOT NULL
              THEN a.approval_date - a.apply_date END), 1) AS avg_days_taken
FROM Officer o
LEFT JOIN Application a ON o.officer_id = a.officer_id
GROUP BY o.officer_name, o.assigned_state
HAVING COUNT(a.application_id) > 0
ORDER BY approval_rate_pct DESC;

-- ============================================================
--  END OF FILE
-- ============================================================
COMMIT;
