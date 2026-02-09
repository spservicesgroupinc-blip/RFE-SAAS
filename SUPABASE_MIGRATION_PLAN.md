# Supabase Migration Plan: RFE App

## Executive Summary

This document outlines the complete migration strategy for the RFE Spray Foam application from Google App Script backend to Supabase for production-ready, multi-tenant SaaS deployment.

**Supabase Project Details:**
- Project URL: `https://sjivzjaktkkqfqmxqvox.supabase.co`
- Publishable API Key: `sb_publishable_zIYd1bH0-fHOhEoOnPHx5w_FwW6xPLr`

---

## 1. Current Architecture Analysis

### 1.1 Current Backend (Google App Script)

**Data Storage:**
- Master spreadsheet for user authentication
- Per-company spreadsheets for business data
- Google Drive folders for file storage (PDFs, images)

**Key Features:**
- Admin/Crew authentication with role-based access
- Estimate/job management
- Customer database
- Inventory tracking
- Equipment tracking
- Purchase orders
- Material usage logs
- Profit & Loss reporting
- Work order generation
- Image uploads
- PDF generation and storage

### 1.2 Data Models (from types.ts)

**Core Entities:**
1. **Users** - Admin accounts with company ownership
2. **Companies** - Multi-tenant company profiles
3. **Customers** - Customer database per company
4. **Estimates** - Job estimates with complex calculation data
5. **Inventory** - Warehouse inventory items
6. **Equipment** - Equipment tracking with last seen location
7. **Purchase Orders** - Material ordering
8. **Material Logs** - Usage tracking
9. **Profit/Loss Records** - Financial reporting
10. **Work Orders** - Crew job sheets

---

## 2. Multi-Tenant Architecture Design

### 2.1 Tenant Isolation Strategy

**Option A: Database-per-Tenant (RECOMMENDED)**
- Each company gets their own Supabase database
- Complete data isolation
- Independent scaling
- Easier compliance (data sovereignty)

**Option B: Schema-per-Tenant**
- Single database with schemas per company
- Cost-effective for smaller deployments
- Requires careful RLS policy management

**Option C: Row-Level Security (Alternative)**
- Single database with `company_id` column on all tables
- Most cost-effective
- Requires robust RLS policies

**RECOMMENDATION:** Start with **Option C (RLS)** for initial deployment due to:
- Easier management for small-medium scale
- Lower infrastructure costs
- Supabase's excellent RLS support
- Can migrate to Option A later if needed

### 2.2 Database Schema Design

```sql
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
    folder_id TEXT, -- For Drive migration (optional)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Users Table (Authentication)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('admin', 'crew')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ
);

-- 3. Company Settings
CREATE TABLE company_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    setting_key TEXT NOT NULL,
    setting_value JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, setting_key)
);

-- 4. Customers
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

-- 5. Estimates (Core Business Logic)
CREATE TABLE estimates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    date DATE NOT NULL,
    status TEXT DEFAULT 'Draft' CHECK (status IN ('Draft', 'Work Order', 'Invoiced', 'Paid', 'Archived')),
    execution_status TEXT DEFAULT 'Not Started' CHECK (execution_status IN ('Not Started', 'In Progress', 'Completed')),
    
    -- Input Parameters (JSONB for flexibility)
    inputs JSONB NOT NULL,
    
    -- Calculation Results
    results JSONB NOT NULL,
    
    -- Materials
    materials JSONB NOT NULL,
    
    -- Pricing & Expenses
    expenses JSONB,
    total_value DECIMAL(10, 2),
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
    
    -- Actuals (Crew Input)
    actuals JSONB,
    
    -- Financials
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

-- 6. Inventory Items
CREATE TABLE inventory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    quantity DECIMAL(10, 2) DEFAULT 0,
    unit TEXT NOT NULL,
    unit_cost DECIMAL(10, 2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Equipment
CREATE TABLE equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT DEFAULT 'Available' CHECK (status IN ('Available', 'In Use', 'Maintenance', 'Lost')),
    last_seen JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Purchase Orders
CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    vendor_name TEXT NOT NULL,
    status TEXT DEFAULT 'Draft' CHECK (status IN ('Draft', 'Sent', 'Received', 'Cancelled')),
    items JSONB NOT NULL,
    total_cost DECIMAL(10, 2),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Material Usage Logs
CREATE TABLE material_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    job_id UUID REFERENCES estimates(id) ON DELETE SET NULL,
    customer_name TEXT NOT NULL,
    material_name TEXT NOT NULL,
    quantity DECIMAL(10, 2) NOT NULL,
    unit TEXT NOT NULL,
    logged_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Profit & Loss Records
CREATE TABLE profit_loss (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    date_paid DATE NOT NULL,
    job_id UUID REFERENCES estimates(id) ON DELETE SET NULL,
    customer_name TEXT,
    invoice_number TEXT,
    revenue DECIMAL(10, 2),
    chemical_cost DECIMAL(10, 2),
    labor_cost DECIMAL(10, 2),
    inventory_cost DECIMAL(10, 2),
    misc_cost DECIMAL(10, 2),
    total_cogs DECIMAL(10, 2),
    net_profit DECIMAL(10, 2),
    margin_percent DECIMAL(5, 2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Trial Memberships (Pre-signup leads)
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
CREATE INDEX idx_customers_company ON customers(company_id);
CREATE INDEX idx_estimates_company ON estimates(company_id);
CREATE INDEX idx_estimates_customer ON estimates(customer_id);
CREATE INDEX idx_estimates_status ON estimates(status);
CREATE INDEX idx_inventory_company ON inventory_items(company_id);
CREATE INDEX idx_equipment_company ON equipment(company_id);
CREATE INDEX idx_material_logs_company ON material_logs(company_id);
CREATE INDEX idx_material_logs_job ON material_logs(job_id);
CREATE INDEX idx_purchase_orders_company ON purchase_orders(company_id);
CREATE INDEX idx_profit_loss_company ON profit_loss(company_id);

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimates ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE material_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE profit_loss ENABLE ROW LEVEL SECURITY;

-- Helper function to get user's company_id
CREATE OR REPLACE FUNCTION get_user_company_id()
RETURNS UUID AS $$
    SELECT company_id FROM users WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER;

-- Companies: Users can only see their own company
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

-- Company Settings: Company-scoped access
CREATE POLICY "Company settings access"
    ON company_settings FOR ALL
    USING (company_id = get_user_company_id());

-- Customers: Company-scoped access
CREATE POLICY "Customers access"
    ON customers FOR ALL
    USING (company_id = get_user_company_id());

-- Estimates: Company-scoped access
CREATE POLICY "Estimates access"
    ON estimates FOR ALL
    USING (company_id = get_user_company_id());

-- Inventory: Company-scoped access
CREATE POLICY "Inventory access"
    ON inventory_items FOR ALL
    USING (company_id = get_user_company_id());

-- Equipment: Company-scoped access
CREATE POLICY "Equipment access"
    ON equipment FOR ALL
    USING (company_id = get_user_company_id());

-- Purchase Orders: Company-scoped access
CREATE POLICY "Purchase orders access"
    ON purchase_orders FOR ALL
    USING (company_id = get_user_company_id());

-- Material Logs: Company-scoped access
CREATE POLICY "Material logs access"
    ON material_logs FOR ALL
    USING (company_id = get_user_company_id());

-- Profit/Loss: Company-scoped access
CREATE POLICY "Profit loss access"
    ON profit_loss FOR ALL
    USING (company_id = get_user_company_id());
```

---

## 3. Authentication Migration

### 3.1 Supabase Auth Setup

**Authentication Flow:**

1. **Admin Signup:**
   ```typescript
   // Sign up with Supabase Auth
   const { data, error } = await supabase.auth.signUp({
       email: email,
       password: password,
       options: {
           data: {
               username: username,
               company_name: companyName,
               role: 'admin'
           }
       }
   });
   
   // Create company and user records via trigger or function
   ```

2. **Admin Login:**
   ```typescript
   const { data, error } = await supabase.auth.signInWithPassword({
       email: username, // or email
       password: password
   });
   ```

3. **Crew Login with PIN:**
   ```typescript
   // Custom function to validate crew PIN
   const { data, error } = await supabase.rpc('crew_login', {
       company_username: username,
       pin: pin
   });
   
   // Returns a custom token for crew access
   ```

### 3.2 Database Trigger for User Creation

```sql
-- Function to create company and user on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
    crew_pin TEXT;
BEGIN
    -- Generate 4-digit crew PIN
    crew_pin := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');
    
    -- Create company
    INSERT INTO companies (company_name, crew_access_pin, email)
    VALUES (
        NEW.raw_user_meta_data->>'company_name',
        crew_pin,
        NEW.email
    )
    RETURNING id INTO new_company_id;
    
    -- Create user record
    INSERT INTO users (id, username, email, company_id, role)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'username',
        NEW.email,
        new_company_id,
        'admin'
    );
    
    -- Initialize default settings
    INSERT INTO company_settings (company_id, setting_key, setting_value)
    VALUES
        (new_company_id, 'warehouse_counts', '{"openCellSets": 0, "closedCellSets": 0}'::jsonb),
        (new_company_id, 'lifetime_usage', '{"openCell": 0, "closedCell": 0}'::jsonb),
        (new_company_id, 'costs', '{"openCell": 2000, "closedCell": 2600, "laborRate": 85}'::jsonb),
        (new_company_id, 'yields', '{"openCell": 16000, "closedCell": 4000, "openCellStrokes": 6600, "closedCellStrokes": 6600}'::jsonb);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users insert
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();
```

### 3.3 Crew Login Function

```sql
-- Custom function for crew login with PIN
CREATE OR REPLACE FUNCTION crew_login(company_username TEXT, pin TEXT)
RETURNS TABLE(
    user_id UUID,
    username TEXT,
    company_name TEXT,
    company_id UUID,
    role TEXT
) AS $$
DECLARE
    target_company companies%ROWTYPE;
BEGIN
    -- Find company by username
    SELECT c.* INTO target_company
    FROM companies c
    JOIN users u ON u.company_id = c.id
    WHERE u.username = company_username AND u.role = 'admin'
    LIMIT 1;
    
    -- Validate PIN
    IF target_company.id IS NULL THEN
        RAISE EXCEPTION 'Company not found';
    END IF;
    
    IF target_company.crew_access_pin != pin THEN
        RAISE EXCEPTION 'Invalid PIN';
    END IF;
    
    -- Return crew session info
    RETURN QUERY
    SELECT
        gen_random_uuid() AS user_id,
        'crew_' || target_company.id::TEXT AS username,
        target_company.company_name,
        target_company.id AS company_id,
        'crew'::TEXT AS role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## 4. API Layer Migration

### 4.1 New API Service Structure

Replace `/services/api.ts` with Supabase client:

```typescript
// services/supabase.ts
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://sjivzjaktkkqfqmxqvox.supabase.co';
const supabaseKey = 'sb_publishable_zIYd1bH0-fHOhEoOnPHx5w_FwW6xPLr';

export const supabase = createClient(supabaseUrl, supabaseKey);

// Helper to get current user's company_id
export async function getUserCompanyId(): Promise<string | null> {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return null;
    
    const { data } = await supabase
        .from('users')
        .select('company_id')
        .eq('id', user.id)
        .single();
    
    return data?.company_id || null;
}
```

### 4.2 API Function Mapping

**Old → New API Calls:**

| Old Google Script Action | New Supabase Implementation |
|--------------------------|----------------------------|
| `LOGIN` | `supabase.auth.signInWithPassword()` |
| `SIGNUP` | `supabase.auth.signUp()` |
| `CREW_LOGIN` | `supabase.rpc('crew_login')` |
| `SYNC_DOWN` | Multiple `supabase.from().select()` calls |
| `SYNC_UP` | Multiple `supabase.from().upsert()` calls |
| `START_JOB` | `supabase.from('estimates').update()` |
| `COMPLETE_JOB` | Transaction with multiple updates |
| `MARK_JOB_PAID` | `supabase.from('estimates').update()` + P&L insert |
| `DELETE_ESTIMATE` | `supabase.from('estimates').delete()` |
| `SAVE_PDF` | Supabase Storage upload |
| `UPLOAD_IMAGE` | Supabase Storage upload |
| `CREATE_WORK_ORDER` | Store work order data in DB |

### 4.3 Example: SyncDown Migration

**Before (Google Script):**
```typescript
export const syncDown = async (spreadsheetId: string) => {
  const result = await apiRequest({ 
    action: 'SYNC_DOWN', 
    payload: { spreadsheetId } 
  });
  return result.data;
};
```

**After (Supabase):**
```typescript
export const syncDown = async (): Promise<Partial<CalculatorState> | null> => {
    const companyId = await getUserCompanyId();
    if (!companyId) return null;
    
    // Fetch all data in parallel
    const [
        { data: settings },
        { data: customers },
        { data: estimates },
        { data: inventory },
        { data: equipment },
        { data: purchaseOrders },
        { data: materialLogs },
        { data: company }
    ] = await Promise.all([
        supabase.from('company_settings').select('*').eq('company_id', companyId),
        supabase.from('customers').select('*').eq('company_id', companyId),
        supabase.from('estimates').select('*').eq('company_id', companyId),
        supabase.from('inventory_items').select('*').eq('company_id', companyId),
        supabase.from('equipment').select('*').eq('company_id', companyId),
        supabase.from('purchase_orders').select('*').eq('company_id', companyId),
        supabase.from('material_logs').select('*').eq('company_id', companyId),
        supabase.from('companies').select('*').eq('id', companyId).single()
    ]);
    
    // Transform settings array to object
    const settingsObj: any = {};
    settings?.forEach(s => {
        settingsObj[s.setting_key] = s.setting_value;
    });
    
    // Build warehouse object
    const warehouseCounts = settingsObj.warehouse_counts || { openCellSets: 0, closedCellSets: 0 };
    const warehouse = {
        ...warehouseCounts,
        items: inventory || []
    };
    
    return {
        companyProfile: company,
        customers: customers || [],
        savedEstimates: estimates || [],
        warehouse,
        equipment: equipment || [],
        purchaseOrders: purchaseOrders || [],
        materialLogs: materialLogs || [],
        lifetimeUsage: settingsObj.lifetime_usage || { openCell: 0, closedCell: 0 },
        yields: settingsObj.yields,
        costs: settingsObj.costs,
        expenses: settingsObj.expenses,
        sqFtRates: settingsObj.sqFtRates,
        pricingMode: settingsObj.pricingMode
    };
};
```

---

## 5. File Storage Migration

### 5.1 Supabase Storage Setup

**Create Storage Buckets:**

1. **company-files** - For PDFs, work orders, general documents
2. **job-photos** - For site photos from crews

**Bucket Policies:**
```sql
-- Allow authenticated users to upload to their company folder
CREATE POLICY "Company file access"
ON storage.objects FOR ALL
USING (
    bucket_id = 'company-files' AND
    auth.uid() IS NOT NULL AND
    (storage.foldername(name))[1] = (SELECT company_id::TEXT FROM users WHERE id = auth.uid())
);

CREATE POLICY "Job photos access"
ON storage.objects FOR ALL
USING (
    bucket_id = 'job-photos' AND
    auth.uid() IS NOT NULL AND
    (storage.foldername(name))[1] = (SELECT company_id::TEXT FROM users WHERE id = auth.uid())
);
```

### 5.2 File Upload Implementation

```typescript
// services/storage.ts
import { supabase, getUserCompanyId } from './supabase';

export async function uploadPDF(
    fileName: string, 
    base64Data: string, 
    estimateId?: string
): Promise<string | null> {
    const companyId = await getUserCompanyId();
    if (!companyId) return null;
    
    // Convert base64 to blob
    const base64String = base64Data.includes(',') 
        ? base64Data.split(',')[1] 
        : base64Data;
    const blob = base64ToBlob(base64String, 'application/pdf');
    
    // Upload to Supabase Storage
    const path = `${companyId}/${estimateId || 'misc'}/${fileName}`;
    const { data, error } = await supabase.storage
        .from('company-files')
        .upload(path, blob, {
            contentType: 'application/pdf',
            upsert: true
        });
    
    if (error) {
        console.error('Upload error:', error);
        return null;
    }
    
    // Get public URL
    const { data: urlData } = supabase.storage
        .from('company-files')
        .getPublicUrl(path);
    
    return urlData.publicUrl;
}

export async function uploadImage(
    base64Data: string, 
    fileName: string = 'image.jpg'
): Promise<string | null> {
    const companyId = await getUserCompanyId();
    if (!companyId) return null;
    
    const base64String = base64Data.includes(',') 
        ? base64Data.split(',')[1] 
        : base64Data;
    const blob = base64ToBlob(base64String, 'image/jpeg');
    
    const timestamp = Date.now();
    const path = `${companyId}/${timestamp}_${fileName}`;
    
    const { data, error } = await supabase.storage
        .from('job-photos')
        .upload(path, blob, {
            contentType: 'image/jpeg'
        });
    
    if (error) return null;
    
    const { data: urlData } = supabase.storage
        .from('job-photos')
        .getPublicUrl(path);
    
    return urlData.publicUrl;
}

function base64ToBlob(base64: string, contentType: string): Blob {
    const byteCharacters = atob(base64);
    const byteArrays = [];
    
    for (let i = 0; i < byteCharacters.length; i++) {
        byteArrays.push(byteCharacters.charCodeAt(i));
    }
    
    return new Blob([new Uint8Array(byteArrays)], { type: contentType });
}
```

---

## 6. Data Migration Strategy

### 6.1 Migration Script Overview

Create a Node.js script to migrate existing data from Google Sheets to Supabase:

```javascript
// migration/migrate-from-google-sheets.js
const { google } = require('googleapis');
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
    'https://sjivzjaktkkqfqmxqvox.supabase.co',
    'YOUR_SERVICE_ROLE_KEY' // Use service role key for migration
);

async function migrateCompany(spreadsheetId, companyName, username, crewPin) {
    // 1. Create company
    const { data: company, error: companyError } = await supabase
        .from('companies')
        .insert({
            company_name: companyName,
            crew_access_pin: crewPin
        })
        .select()
        .single();
    
    if (companyError) throw companyError;
    
    // 2. Create admin user (requires auth.admin)
    const { data: authUser, error: authError } = await supabase.auth.admin.createUser({
        email: `${username}@company.local`, // or real email
        password: 'temporary_password_123',
        email_confirm: true,
        user_metadata: {
            username: username,
            company_name: companyName,
            role: 'admin'
        }
    });
    
    if (authError) throw authError;
    
    // 3. Migrate customers
    const customersSheet = await getSheetData(spreadsheetId, 'Customers_DB');
    const customers = parseCustomersFromSheet(customersSheet);
    await supabase.from('customers').insert(
        customers.map(c => ({ ...c, company_id: company.id }))
    );
    
    // 4. Migrate estimates
    const estimatesSheet = await getSheetData(spreadsheetId, 'Estimates_DB');
    const estimates = parseEstimatesFromSheet(estimatesSheet);
    await supabase.from('estimates').insert(
        estimates.map(e => ({ ...e, company_id: company.id }))
    );
    
    // 5. Migrate inventory
    // ... similar pattern
    
    // 6. Migrate equipment
    // ... similar pattern
    
    // 7. Migrate settings
    const settingsSheet = await getSheetData(spreadsheetId, 'Settings_DB');
    const settings = parseSettingsFromSheet(settingsSheet);
    await supabase.from('company_settings').insert(
        settings.map(s => ({ ...s, company_id: company.id }))
    );
    
    console.log(`Migration complete for ${companyName}`);
}

// Helper functions
async function getSheetData(spreadsheetId, sheetName) {
    // Use Google Sheets API to fetch data
    const sheets = google.sheets('v4');
    const response = await sheets.spreadsheets.values.get({
        spreadsheetId,
        range: `${sheetName}!A:Z`
    });
    return response.data.values;
}

function parseCustomersFromSheet(rows) {
    // Parse customer data from sheet format
    return rows.slice(1).map(row => {
        const jsonData = JSON.parse(row[9] || '{}');
        return {
            id: row[0],
            name: row[1],
            address: row[2],
            city: row[3],
            state: row[4],
            zip: row[5],
            phone: row[6],
            email: row[7],
            status: row[8],
            notes: jsonData.notes || ''
        };
    });
}

// ... additional parsing functions
```

### 6.2 Migration Checklist

1. **Pre-Migration:**
   - [ ] Backup all Google Sheets data
   - [ ] Set up Supabase project
   - [ ] Create database schema
   - [ ] Configure RLS policies
   - [ ] Create storage buckets
   - [ ] Test migration script on sample data

2. **Migration Execution:**
   - [ ] Run migration script for each company
   - [ ] Verify data integrity
   - [ ] Migrate files to Supabase Storage
   - [ ] Update file URLs in database

3. **Post-Migration:**
   - [ ] Verify all data migrated correctly
   - [ ] Test authentication flows
   - [ ] Test CRUD operations
   - [ ] Performance testing
   - [ ] User acceptance testing

---

## 7. Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Set up Supabase project
- [ ] Create database schema with RLS
- [ ] Install Supabase client library
- [ ] Create authentication flows
- [ ] Set up storage buckets

### Phase 2: Core API Migration (Week 2)
- [ ] Migrate authentication (login, signup, crew login)
- [ ] Migrate sync operations (syncDown, syncUp)
- [ ] Migrate estimate CRUD operations
- [ ] Migrate customer operations
- [ ] Migrate inventory/equipment operations

### Phase 3: Advanced Features (Week 3)
- [ ] Migrate file uploads (PDFs, images)
- [ ] Migrate job completion flow
- [ ] Migrate P&L calculations
- [ ] Migrate material logs
- [ ] Migrate purchase orders

### Phase 4: Testing & Migration (Week 4)
- [ ] Create data migration scripts
- [ ] Migrate existing data
- [ ] Comprehensive testing
- [ ] Performance optimization
- [ ] Production deployment

---

## 8. Code Changes Required

### 8.1 Package Dependencies

Add to `package.json`:
```json
{
  "dependencies": {
    "@supabase/supabase-js": "^2.39.0",
    "jspdf": "2.5.1",
    "jspdf-autotable": "3.8.2",
    "lucide-react": "^0.561.0",
    "react": "^19.2.3",
    "react-dom": "^19.2.3"
  }
}
```

### 8.2 New Files to Create

1. **`services/supabase.ts`** - Supabase client initialization
2. **`services/storage.ts`** - File upload/download functions
3. **`services/auth.ts`** - Authentication helpers
4. **`services/database.ts`** - Database CRUD operations
5. **`migration/schema.sql`** - Database schema
6. **`migration/migrate-data.js`** - Data migration script
7. **`.env.local`** - Environment variables

### 8.3 Files to Modify

1. **`services/api.ts`** - Replace Google Script calls with Supabase
2. **`constants.ts`** - Add Supabase config
3. **`context/CalculatorContext.tsx`** - Update API calls
4. **`components/LoginPage.tsx`** - Update auth flow
5. All components making API calls

### 8.4 Files to Remove

1. **`backend/Code.js`** - Google App Script backend (keep for reference)

---

## 9. Environment Variables

Create `.env.local`:
```bash
VITE_SUPABASE_URL=https://sjivzjaktkkqfqmxqvox.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_zIYd1bH0-fHOhEoOnPHx5w_FwW6xPLr
```

Update `vite.config.ts` to load env variables:
```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  define: {
    'process.env': {}
  }
});
```

---

## 10. Security Considerations

### 10.1 Row Level Security (RLS)
- ✅ All tables have RLS enabled
- ✅ Policies enforce company_id matching
- ✅ Crew login uses custom function with validation

### 10.2 Authentication
- ✅ Use Supabase Auth for secure token management
- ✅ Crew PIN is validated server-side
- ✅ Admin passwords are hashed by Supabase

### 10.3 API Keys
- ✅ Use publishable (anon) key for frontend
- ✅ Service role key only for migrations (never expose)
- ✅ Store keys in environment variables

### 10.4 File Access
- ✅ Storage buckets have RLS policies
- ✅ Files are organized by company_id
- ✅ Public URLs are available but organized

---

## 11. Testing Strategy

### 11.1 Unit Tests
- Database functions (crew_login, triggers)
- API service functions
- Data transformation functions

### 11.2 Integration Tests
- Authentication flows
- CRUD operations
- File uploads
- Job completion flow

### 11.3 End-to-End Tests
- Admin signup → Create estimate → Complete job → Mark paid
- Crew login → View jobs → Complete job
- Multi-tenant isolation verification

---

## 12. Rollback Plan

### 12.1 Parallel Running
- Keep Google Script backend active during transition
- Use feature flag to switch between backends
- Monitor both systems during migration

### 12.2 Quick Rollback
```typescript
// constants.ts
export const USE_SUPABASE = false; // Toggle to rollback

// In api.ts
if (USE_SUPABASE) {
    // New Supabase calls
} else {
    // Old Google Script calls
}
```

---

## 13. Performance Optimizations

### 13.1 Database Indexing
- Added indexes on foreign keys
- Added indexes on commonly queried fields
- Composite indexes for multi-column queries

### 13.2 Query Optimization
- Use parallel Promise.all() for multiple queries
- Implement pagination for large datasets
- Use select() to limit returned fields

### 13.3 Caching Strategy
- Cache company settings in memory
- Cache user session data
- Implement optimistic UI updates

---

## 14. Monitoring & Maintenance

### 14.1 Supabase Dashboard
- Monitor database performance
- Track API usage
- Review authentication logs
- Monitor storage usage

### 14.2 Error Tracking
- Implement error logging
- Set up alerts for critical failures
- Track API response times

### 14.3 Backups
- Supabase automatic daily backups
- Manual backups before major changes
- Test restore procedures

---

## 15. Cost Estimation

### 15.1 Supabase Pricing (Pro Plan - $25/month)
- 8GB database storage
- 100GB bandwidth
- 50GB file storage
- Suitable for 10-50 companies

### 15.2 Scaling Considerations
- Additional storage: $0.125/GB/month
- Additional bandwidth: $0.09/GB
- Team plan for larger deployments

---

## 16. Next Steps

1. **Review and approve this migration plan**
2. **Set up development Supabase project**
3. **Create database schema**
4. **Implement Phase 1 (Foundation)**
5. **Parallel testing with existing system**
6. **Gradual rollout to production**

---

## Appendix A: Quick Reference

### Key Supabase Operations

```typescript
// Authentication
const { data, error } = await supabase.auth.signUp({ email, password });
const { data, error } = await supabase.auth.signInWithPassword({ email, password });
const { data, error } = await supabase.auth.signOut();

// Database
const { data, error } = await supabase.from('table').select('*');
const { data, error } = await supabase.from('table').insert(record);
const { data, error } = await supabase.from('table').update(changes).eq('id', id);
const { data, error } = await supabase.from('table').delete().eq('id', id);

// Storage
const { data, error } = await supabase.storage.from('bucket').upload(path, file);
const { data } = supabase.storage.from('bucket').getPublicUrl(path);

// Custom Functions
const { data, error } = await supabase.rpc('function_name', { params });
```

### Multi-Tenant Pattern

```typescript
// Always include company_id in queries
const companyId = await getUserCompanyId();
const { data } = await supabase
    .from('table')
    .select('*')
    .eq('company_id', companyId);
```

---

## Appendix B: Contact & Support

- **Supabase Documentation**: https://supabase.com/docs
- **Supabase Discord**: https://discord.supabase.com
- **Project Dashboard**: https://supabase.com/dashboard/project/sjivzjaktkkqfqmxqvox

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-09  
**Author:** Migration Planning Team
