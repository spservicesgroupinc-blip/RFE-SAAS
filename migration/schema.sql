-- ============================================
-- RFE APP - SUPABASE DATABASE SCHEMA
-- Multi-Tenant SaaS Architecture
-- Production-Ready PostgreSQL Schema
-- ============================================

-- ============================================
-- CORE TABLES WITH MULTI-TENANT SUPPORT
-- ============================================

-- 1. Companies Table (Tenant Root)
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name TEXT NOT NULL,
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    state TEXT,
    zip TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    logo_url TEXT,
    crew_access_pin TEXT NOT NULL,
    subscription_status TEXT DEFAULT 'Trial' CHECK (subscription_status IN ('Trial', 'Active', 'PastDue', 'Cancelled')),
    folder_id TEXT, -- For Drive migration reference (optional)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Users Table (Links to auth.users)
CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('admin', 'manager', 'crew')),
    full_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ
);

-- 3. Company Settings (Key-Value store for flexibility)
CREATE TABLE company_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    setting_key TEXT NOT NULL,
    setting_value JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, setting_key)
);

-- 4. Customers (CRM)
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    city TEXT,
    state TEXT,
    zip TEXT,
    email TEXT,
    phone TEXT,
    notes TEXT,
    status TEXT DEFAULT 'Active' CHECK (status IN ('Active', 'Archived', 'Lead')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Estimates (Core Business Entity - Jobs/Invoices)
CREATE TABLE estimates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    estimate_number TEXT,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT DEFAULT 'Draft' CHECK (status IN ('Draft', 'Work Order', 'Invoiced', 'Paid', 'Archived')),
    execution_status TEXT DEFAULT 'Not Started' CHECK (execution_status IN ('Not Started', 'In Progress', 'Completed')),
    
    -- Input Parameters (JSONB for calculation inputs)
    inputs JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- Calculation Results (locked snapshot)
    results JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- Materials (planned)
    materials JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- Pricing & Expenses
    expenses JSONB DEFAULT '{}'::jsonb,
    total_value DECIMAL(10, 2) DEFAULT 0,
    total_material_cost DECIMAL(10, 2) DEFAULT 0,
    total_labor_cost DECIMAL(10, 2) DEFAULT 0,
    margin_percent DECIMAL(5, 2) DEFAULT 0,
    pricing_mode TEXT DEFAULT 'level_pricing',
    sqft_rates JSONB,
    
    -- Invoice Details
    invoice_number TEXT,
    invoice_date DATE,
    payment_terms TEXT,
    invoice_lines JSONB,
    
    -- Work Order
    scheduled_date DATE,
    work_order_lines JSONB,
    work_order_sheet_url TEXT,
    
    -- Actuals (Crew completed data)
    actuals JSONB,
    
    -- Financials (P&L locked snapshot)
    financials JSONB,
    
    -- Files
    pdf_link TEXT,
    site_photos TEXT[],
    
    -- Metadata
    notes TEXT,
    inventory_processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Estimate Line Items (Optional normalized view)
CREATE TABLE estimate_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estimate_id UUID REFERENCES estimates(id) ON DELETE CASCADE,
    item_type TEXT CHECK (item_type IN ('Material', 'Labor', 'Fee', 'Custom')),
    description TEXT NOT NULL,
    quantity DECIMAL(10, 2) DEFAULT 1,
    unit_price DECIMAL(10, 2) DEFAULT 0,
    total_amount DECIMAL(10, 2) DEFAULT 0,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Inventory Items (General Supplies)
CREATE TABLE inventory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    quantity DECIMAL(10, 2) DEFAULT 0,
    unit TEXT NOT NULL,
    unit_cost DECIMAL(10, 2) DEFAULT 0,
    reorder_point DECIMAL(10, 2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Chemical Stock (Foam Tanks/Sets)
CREATE TABLE chemical_stock (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    open_cell_sets DECIMAL(10, 2) DEFAULT 0,
    closed_cell_sets DECIMAL(10, 2) DEFAULT 0,
    lifetime_open_cell_used DECIMAL(10, 2) DEFAULT 0,
    lifetime_closed_cell_used DECIMAL(10, 2) DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Equipment (Asset Tracking)
CREATE TABLE equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT DEFAULT 'Available' CHECK (status IN ('Available', 'In Use', 'Maintenance', 'Lost')),
    last_seen JSONB,
    last_seen_job_id UUID REFERENCES estimates(id) ON DELETE SET NULL,
    last_seen_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Purchase Orders
CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    po_number TEXT,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    vendor_name TEXT NOT NULL,
    status TEXT DEFAULT 'Draft' CHECK (status IN ('Draft', 'Sent', 'Received', 'Cancelled')),
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    total_cost DECIMAL(10, 2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Material Usage Logs (Audit Trail)
CREATE TABLE material_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    job_id UUID REFERENCES estimates(id) ON DELETE SET NULL,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    customer_name TEXT NOT NULL,
    material_name TEXT NOT NULL,
    material_type TEXT CHECK (material_type IN ('OpenCell', 'ClosedCell', 'Inventory', 'Equipment')),
    action TEXT CHECK (action IN ('Usage', 'Adjustment', 'Restock')),
    quantity DECIMAL(10, 2) NOT NULL,
    unit TEXT NOT NULL,
    logged_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. Profit & Loss Records
CREATE TABLE profit_loss (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    date_paid DATE NOT NULL,
    job_id UUID REFERENCES estimates(id) ON DELETE SET NULL,
    customer_name TEXT,
    invoice_number TEXT,
    revenue DECIMAL(10, 2) DEFAULT 0,
    chemical_cost DECIMAL(10, 2) DEFAULT 0,
    labor_cost DECIMAL(10, 2) DEFAULT 0,
    inventory_cost DECIMAL(10, 2) DEFAULT 0,
    misc_cost DECIMAL(10, 2) DEFAULT 0,
    total_cogs DECIMAL(10, 2) DEFAULT 0,
    net_profit DECIMAL(10, 2) DEFAULT 0,
    margin_percent DECIMAL(5, 2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. Time Logs (Crew Time Tracking)
CREATE TABLE time_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estimate_id UUID REFERENCES estimates(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    crew_name TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_hours DECIMAL(5, 2),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. Trial Memberships (Pre-signup leads)
CREATE TABLE trial_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

CREATE INDEX idx_users_company ON users(company_id);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);

CREATE INDEX idx_company_settings_company ON company_settings(company_id);
CREATE INDEX idx_company_settings_key ON company_settings(company_id, setting_key);

CREATE INDEX idx_customers_company ON customers(company_id);
CREATE INDEX idx_customers_status ON customers(company_id, status);
CREATE INDEX idx_customers_name ON customers(company_id, name);

CREATE INDEX idx_estimates_company ON estimates(company_id);
CREATE INDEX idx_estimates_customer ON estimates(customer_id);
CREATE INDEX idx_estimates_status ON estimates(company_id, status);
CREATE INDEX idx_estimates_execution_status ON estimates(company_id, execution_status);
CREATE INDEX idx_estimates_date ON estimates(company_id, date DESC);
CREATE INDEX idx_estimates_invoice_number ON estimates(company_id, invoice_number);

CREATE INDEX idx_estimate_items_estimate ON estimate_items(estimate_id);

CREATE INDEX idx_inventory_company ON inventory_items(company_id);
CREATE INDEX idx_equipment_company ON equipment(company_id);
CREATE INDEX idx_equipment_status ON equipment(company_id, status);

CREATE INDEX idx_purchase_orders_company ON purchase_orders(company_id);
CREATE INDEX idx_purchase_orders_status ON purchase_orders(company_id, status);

CREATE INDEX idx_material_logs_company ON material_logs(company_id);
CREATE INDEX idx_material_logs_job ON material_logs(job_id);
CREATE INDEX idx_material_logs_date ON material_logs(company_id, date DESC);

CREATE INDEX idx_profit_loss_company ON profit_loss(company_id);
CREATE INDEX idx_profit_loss_date ON profit_loss(company_id, date_paid DESC);

CREATE INDEX idx_time_logs_estimate ON time_logs(estimate_id);
CREATE INDEX idx_time_logs_user ON time_logs(user_id);

-- ============================================
-- UPDATED_AT TRIGGERS
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_companies_updated_at BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_company_settings_updated_at BEFORE UPDATE ON company_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_estimates_updated_at BEFORE UPDATE ON estimates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_inventory_updated_at BEFORE UPDATE ON inventory_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_equipment_updated_at BEFORE UPDATE ON equipment
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_purchase_orders_updated_at BEFORE UPDATE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_chemical_stock_updated_at BEFORE UPDATE ON chemical_stock
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY (RLS) SETUP
-- ============================================

-- Enable RLS on all tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimates ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimate_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE chemical_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE material_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE profit_loss ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE trial_memberships ENABLE ROW LEVEL SECURITY;

-- Helper function to get user's company_id
CREATE OR REPLACE FUNCTION get_user_company_id()
RETURNS UUID AS $$
    SELECT company_id FROM users WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER;

-- Companies: Users can only see/update their own company
CREATE POLICY "Users can view own company"
    ON companies FOR SELECT
    USING (id = get_user_company_id());

CREATE POLICY "Users can update own company"
    ON companies FOR UPDATE
    USING (id = get_user_company_id());

-- Users: Can view users in same company
CREATE POLICY "Users can view company users"
    ON users FOR SELECT
    USING (company_id = get_user_company_id());

-- Company Settings: Full access for company members
CREATE POLICY "Company settings select"
    ON company_settings FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Company settings insert"
    ON company_settings FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Company settings update"
    ON company_settings FOR UPDATE
    USING (company_id = get_user_company_id());

CREATE POLICY "Company settings delete"
    ON company_settings FOR DELETE
    USING (company_id = get_user_company_id());

-- Customers: Full CRUD for company members
CREATE POLICY "Customers select"
    ON customers FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Customers insert"
    ON customers FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Customers update"
    ON customers FOR UPDATE
    USING (company_id = get_user_company_id());

CREATE POLICY "Customers delete"
    ON customers FOR DELETE
    USING (company_id = get_user_company_id());

-- Estimates: Full CRUD for company members
CREATE POLICY "Estimates select"
    ON estimates FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Estimates insert"
    ON estimates FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Estimates update"
    ON estimates FOR UPDATE
    USING (company_id = get_user_company_id());

CREATE POLICY "Estimates delete"
    ON estimates FOR DELETE
    USING (company_id = get_user_company_id());

-- Estimate Items: Access through parent estimate
CREATE POLICY "Estimate items select"
    ON estimate_items FOR SELECT
    USING (
        estimate_id IN (
            SELECT id FROM estimates WHERE company_id = get_user_company_id()
        )
    );

CREATE POLICY "Estimate items insert"
    ON estimate_items FOR INSERT
    WITH CHECK (
        estimate_id IN (
            SELECT id FROM estimates WHERE company_id = get_user_company_id()
        )
    );

CREATE POLICY "Estimate items update"
    ON estimate_items FOR UPDATE
    USING (
        estimate_id IN (
            SELECT id FROM estimates WHERE company_id = get_user_company_id()
        )
    );

CREATE POLICY "Estimate items delete"
    ON estimate_items FOR DELETE
    USING (
        estimate_id IN (
            SELECT id FROM estimates WHERE company_id = get_user_company_id()
        )
    );

-- Inventory: Full CRUD for company members
CREATE POLICY "Inventory select"
    ON inventory_items FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Inventory insert"
    ON inventory_items FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Inventory update"
    ON inventory_items FOR UPDATE
    USING (company_id = get_user_company_id());

CREATE POLICY "Inventory delete"
    ON inventory_items FOR DELETE
    USING (company_id = get_user_company_id());

-- Chemical Stock: Full CRUD for company members
CREATE POLICY "Chemical stock select"
    ON chemical_stock FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Chemical stock insert"
    ON chemical_stock FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Chemical stock update"
    ON chemical_stock FOR UPDATE
    USING (company_id = get_user_company_id());

-- Equipment: Full CRUD for company members
CREATE POLICY "Equipment select"
    ON equipment FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Equipment insert"
    ON equipment FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Equipment update"
    ON equipment FOR UPDATE
    USING (company_id = get_user_company_id());

CREATE POLICY "Equipment delete"
    ON equipment FOR DELETE
    USING (company_id = get_user_company_id());

-- Purchase Orders: Full CRUD for company members
CREATE POLICY "Purchase orders select"
    ON purchase_orders FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Purchase orders insert"
    ON purchase_orders FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Purchase orders update"
    ON purchase_orders FOR UPDATE
    USING (company_id = get_user_company_id());

CREATE POLICY "Purchase orders delete"
    ON purchase_orders FOR DELETE
    USING (company_id = get_user_company_id());

-- Material Logs: Full access for company members
CREATE POLICY "Material logs select"
    ON material_logs FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Material logs insert"
    ON material_logs FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Material logs delete"
    ON material_logs FOR DELETE
    USING (company_id = get_user_company_id());

-- Profit/Loss: Full access for company members
CREATE POLICY "Profit loss select"
    ON profit_loss FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Profit loss insert"
    ON profit_loss FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

-- Time Logs: Access through parent estimate
CREATE POLICY "Time logs select"
    ON time_logs FOR SELECT
    USING (
        estimate_id IN (
            SELECT id FROM estimates WHERE company_id = get_user_company_id()
        )
    );

CREATE POLICY "Time logs insert"
    ON time_logs FOR INSERT
    WITH CHECK (
        estimate_id IN (
            SELECT id FROM estimates WHERE company_id = get_user_company_id()
        )
    );

-- Trial Memberships: Allow anyone to insert (public signup)
CREATE POLICY "Trial memberships public insert"
    ON trial_memberships FOR INSERT
    WITH CHECK (true);

-- ============================================
-- USER CREATION TRIGGER
-- ============================================

-- Function to create company and user record on auth signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    crew_pin TEXT;
BEGIN
    -- Generate 4-digit crew PIN
    crew_pin := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
    
    -- Create company
    INSERT INTO companies (
        company_name, 
        crew_access_pin, 
        email
    )
    VALUES (
        COALESCE(NEW.raw_user_meta_data->>'company_name', 'New Company'),
        crew_pin,
        NEW.email
    )
    RETURNING id INTO new_company_id;
    
    -- Create user record
    INSERT INTO users (
        id, 
        username, 
        email, 
        company_id, 
        role,
        full_name
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'username', SPLIT_PART(NEW.email, '@', 1)),
        NEW.email,
        new_company_id,
        COALESCE(NEW.raw_user_meta_data->>'role', 'admin'),
        NEW.raw_user_meta_data->>'full_name'
    );
    
    -- Initialize chemical stock
    INSERT INTO chemical_stock (company_id)
    VALUES (new_company_id);
    
    -- Initialize default settings
    INSERT INTO company_settings (company_id, setting_key, setting_value)
    VALUES
        (new_company_id, 'warehouse_counts', '{"openCellSets": 0, "closedCellSets": 0}'::jsonb),
        (new_company_id, 'lifetime_usage', '{"openCell": 0, "closedCell": 0}'::jsonb),
        (new_company_id, 'costs', '{"openCell": 2000, "closedCell": 2600, "laborRate": 85}'::jsonb),
        (new_company_id, 'yields', '{"openCell": 16000, "closedCell": 4000, "openCellStrokes": 6600, "closedCellStrokes": 6600}'::jsonb),
        (new_company_id, 'expenses', '{"manHours": 0, "laborRate": 85, "tripCharge": 0, "fuelSurcharge": 0, "other": {"description": "", "amount": 0}}'::jsonb);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users insert
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- ============================================
-- CREW LOGIN FUNCTION
-- ============================================

-- Custom function for crew login with PIN
CREATE OR REPLACE FUNCTION crew_login(
    company_username TEXT, 
    pin TEXT
)
RETURNS TABLE(
    company_id UUID,
    company_name TEXT,
    username TEXT,
    role TEXT,
    success BOOLEAN,
    message TEXT,
    spreadsheet_id TEXT
) AS $$
DECLARE
    target_company companies%ROWTYPE;
    admin_user users%ROWTYPE;
BEGIN
    -- Find company by admin username
    SELECT u.* INTO admin_user
    FROM users u
    WHERE u.username = company_username 
        AND u.role = 'admin'
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT 
            NULL::UUID, 
            ''::TEXT, 
            ''::TEXT, 
            ''::TEXT, 
            false, 
            'Company username not found'::TEXT,
            ''::TEXT;
        RETURN;
    END IF;
    
    -- Get company
    SELECT c.* INTO target_company
    FROM companies c
    WHERE c.id = admin_user.company_id;
    
    -- Validate PIN
    IF target_company.crew_access_pin != pin THEN
        RETURN QUERY SELECT 
            NULL::UUID, 
            ''::TEXT, 
            ''::TEXT, 
            ''::TEXT, 
            false, 
            'Invalid PIN'::TEXT,
            ''::TEXT;
        RETURN;
    END IF;
    
    -- Return success with company info
    RETURN QUERY SELECT
        target_company.id,
        target_company.company_name,
        company_username,
        'crew'::TEXT,
        true,
        'Login successful'::TEXT,
        target_company.id::TEXT; -- Return company_id as spreadsheet_id for compatibility
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- JOB COMPLETION FUNCTION (WITH TRANSACTIONS)
-- ============================================

CREATE OR REPLACE FUNCTION process_job_completion(
    p_estimate_id UUID,
    p_actuals JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_company_id UUID;
    v_estimate estimates%ROWTYPE;
    v_open_cell_used DECIMAL;
    v_closed_cell_used DECIMAL;
    v_result JSONB;
BEGIN
    -- Get estimate and company_id
    SELECT * INTO v_estimate FROM estimates WHERE id = p_estimate_id;
    
    IF v_estimate.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Estimate not found');
    END IF;
    
    IF v_estimate.inventory_processed THEN
        RETURN jsonb_build_object('success', false, 'message', 'Job already completed');
    END IF;
    
    v_company_id := v_estimate.company_id;
    v_open_cell_used := COALESCE((p_actuals->>'openCellSets')::DECIMAL, 0);
    v_closed_cell_used := COALESCE((p_actuals->>'closedCellSets')::DECIMAL, 0);
    
    -- START TRANSACTION (implicit in function)
    
    -- Update chemical stock with proper locking
    UPDATE chemical_stock
    SET 
        open_cell_sets = GREATEST(0, open_cell_sets - v_open_cell_used),
        closed_cell_sets = GREATEST(0, closed_cell_sets - v_closed_cell_used),
        lifetime_open_cell_used = lifetime_open_cell_used + v_open_cell_used,
        lifetime_closed_cell_used = lifetime_closed_cell_used + v_closed_cell_used,
        updated_at = NOW()
    WHERE company_id = v_company_id;
    
    -- Update inventory items if present in actuals
    IF p_actuals ? 'inventory' THEN
        DECLARE
            inv_item JSONB;
        BEGIN
            FOR inv_item IN SELECT * FROM jsonb_array_elements(p_actuals->'inventory')
            LOOP
                UPDATE inventory_items
                SET 
                    quantity = GREATEST(0, quantity - (inv_item->>'quantity')::DECIMAL),
                    updated_at = NOW()
                WHERE id = (inv_item->>'id')::UUID
                    AND company_id = v_company_id;
            END LOOP;
        END;
    END IF;
    
    -- Update equipment last seen
    IF jsonb_typeof(v_estimate.materials->'equipment') = 'array' THEN
        DECLARE
            equip_item JSONB;
        BEGIN
            FOR equip_item IN SELECT * FROM jsonb_array_elements(v_estimate.materials->'equipment')
            LOOP
                UPDATE equipment
                SET 
                    status = 'Available',
                    last_seen_job_id = p_estimate_id,
                    last_seen_date = NOW(),
                    last_seen = jsonb_build_object(
                        'jobId', p_estimate_id,
                        'customerName', v_estimate.inputs->>'customerName',
                        'date', NOW(),
                        'crewMember', p_actuals->>'completedBy'
                    ),
                    updated_at = NOW()
                WHERE id = (equip_item->>'id')::UUID
                    AND company_id = v_company_id;
            END LOOP;
        END;
    END IF;
    
    -- Log material usage
    INSERT INTO material_logs (
        company_id, date, job_id, customer_name, 
        material_name, material_type, action, quantity, unit, logged_by
    )
    VALUES
        (v_company_id, CURRENT_DATE, p_estimate_id, 
         COALESCE((SELECT name FROM customers WHERE id = v_estimate.customer_id), 'Unknown'),
         'Open Cell Foam', 'OpenCell', 'Usage', v_open_cell_used, 'Sets', 
         COALESCE(p_actuals->>'completedBy', 'Crew')),
        (v_company_id, CURRENT_DATE, p_estimate_id,
         COALESCE((SELECT name FROM customers WHERE id = v_estimate.customer_id), 'Unknown'),
         'Closed Cell Foam', 'ClosedCell', 'Usage', v_closed_cell_used, 'Sets',
         COALESCE(p_actuals->>'completedBy', 'Crew'));
    
    -- Update estimate
    UPDATE estimates
    SET 
        execution_status = 'Completed',
        actuals = p_actuals,
        inventory_processed = true,
        updated_at = NOW()
    WHERE id = p_estimate_id;
    
    RETURN jsonb_build_object(
        'success', true, 
        'message', 'Job completed successfully',
        'open_cell_used', v_open_cell_used,
        'closed_cell_used', v_closed_cell_used
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false, 
            'message', SQLERRM
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to get company profile
CREATE OR REPLACE FUNCTION get_company_profile(p_company_id UUID)
RETURNS JSONB AS $$
    SELECT row_to_json(c)::jsonb
    FROM companies c
    WHERE c.id = p_company_id;
$$ LANGUAGE SQL SECURITY DEFINER;

-- Function to calculate P&L on payment
CREATE OR REPLACE FUNCTION calculate_job_financials(
    p_estimate_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_estimate estimates%ROWTYPE;
    v_costs JSONB;
    v_open_cell_cost DECIMAL;
    v_closed_cell_cost DECIMAL;
    v_labor_rate DECIMAL;
    v_chem_cost DECIMAL;
    v_labor_cost DECIMAL;
    v_inv_cost DECIMAL;
    v_misc_cost DECIMAL;
    v_total_cogs DECIMAL;
    v_net_profit DECIMAL;
    v_margin DECIMAL;
BEGIN
    -- Get estimate
    SELECT * INTO v_estimate FROM estimates WHERE id = p_estimate_id;
    
    -- Get costs
    SELECT setting_value INTO v_costs
    FROM company_settings
    WHERE company_id = v_estimate.company_id AND setting_key = 'costs';
    
    v_open_cell_cost := COALESCE((v_costs->>'openCell')::DECIMAL, 2000);
    v_closed_cell_cost := COALESCE((v_costs->>'closedCell')::DECIMAL, 2600);
    v_labor_rate := COALESCE((v_costs->>'laborRate')::DECIMAL, 85);
    
    -- Calculate costs
    v_chem_cost := 
        COALESCE((v_estimate.actuals->>'openCellSets')::DECIMAL, 0) * v_open_cell_cost +
        COALESCE((v_estimate.actuals->>'closedCellSets')::DECIMAL, 0) * v_closed_cell_cost;
    
    v_labor_cost := 
        COALESCE((v_estimate.actuals->>'laborHours')::DECIMAL, 
                 (v_estimate.expenses->>'manHours')::DECIMAL, 0) * v_labor_rate;
    
    v_inv_cost := 0; -- Calculate from inventory items if needed
    
    v_misc_cost := 
        COALESCE((v_estimate.expenses->>'tripCharge')::DECIMAL, 0) +
        COALESCE((v_estimate.expenses->>'fuelSurcharge')::DECIMAL, 0);
    
    v_total_cogs := v_chem_cost + v_labor_cost + v_inv_cost + v_misc_cost;
    v_net_profit := v_estimate.total_value - v_total_cogs;
    v_margin := CASE WHEN v_estimate.total_value > 0 
                THEN (v_net_profit / v_estimate.total_value) * 100 
                ELSE 0 END;
    
    RETURN jsonb_build_object(
        'revenue', v_estimate.total_value,
        'chemicalCost', v_chem_cost,
        'laborCost', v_labor_cost,
        'inventoryCost', v_inv_cost,
        'miscCost', v_misc_cost,
        'totalCOGS', v_total_cogs,
        'netProfit', v_net_profit,
        'margin', v_margin
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================

COMMENT ON TABLE companies IS 'Multi-tenant root table - each company is a separate tenant';
COMMENT ON TABLE users IS 'User accounts linked to auth.users and scoped to companies';
COMMENT ON TABLE company_settings IS 'Flexible key-value store for company-specific settings';
COMMENT ON TABLE estimates IS 'Core business entity for job estimates/work orders/invoices';
COMMENT ON TABLE chemical_stock IS 'Foam chemical inventory with lifetime usage tracking';
COMMENT ON COLUMN estimates.inputs IS 'Job input parameters (dimensions, settings, etc.)';
COMMENT ON COLUMN estimates.results IS 'Calculated results (areas, costs, materials needed)';
COMMENT ON COLUMN estimates.actuals IS 'Crew-reported actual materials used and time spent';
COMMENT ON FUNCTION get_user_company_id IS 'Helper function for RLS - returns current users company_id';
COMMENT ON FUNCTION crew_login IS 'Authenticates crew members using company username and PIN';
COMMENT ON FUNCTION process_job_completion IS 'Handles job completion with transactional inventory updates';
COMMENT ON FUNCTION calculate_job_financials IS 'Calculates P&L metrics for a completed job';
