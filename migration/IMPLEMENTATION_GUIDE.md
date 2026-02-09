# RFE Foam Pro - Supabase Migration Implementation Guide

## Quick Start

This guide provides step-by-step instructions for migrating the RFE Foam Pro application from Google App Script to Supabase.

---

## Prerequisites

- Node.js 18+ installed
- Supabase account with project created
- Git for version control
- Basic understanding of PostgreSQL

---

## Step 1: Database Setup

### 1.1 Create Supabase Project

✅ Already complete - Project created at: `https://sjivzjaktkkqfqmxqvox.supabase.co`

### 1.2 Run Database Schema

1. Go to your Supabase Dashboard: https://supabase.com/dashboard/project/sjivzjaktkkqfqmxqvox
2. Navigate to **SQL Editor**
3. Create a new query
4. Copy the entire contents of `migration/schema.sql`
5. Paste and run the query
6. Verify all tables were created successfully

**Expected Output:**
- 14 tables created
- Multiple indexes created
- RLS policies enabled
- Triggers and functions created

### 1.3 Verify RLS Policies

Run this query to verify RLS is active:

```sql
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public';
```

All tables should show `rowsecurity = true`.

---

## Step 2: Storage Buckets Setup

### 2.1 Create Storage Buckets

1. Go to **Storage** in Supabase Dashboard
2. Create bucket: `company-files`
   - Public: **Yes**
   - File size limit: 50 MB
   - Allowed MIME types: `application/pdf, image/*`

3. Create bucket: `job-photos`
   - Public: **Yes**
   - File size limit: 10 MB
   - Allowed MIME types: `image/*`

### 2.2 Configure Storage Policies

Run these SQL statements in the SQL Editor:

```sql
-- Policy for company-files bucket
CREATE POLICY "Company files access"
ON storage.objects FOR ALL
USING (
    bucket_id = 'company-files' AND
    auth.uid() IS NOT NULL AND
    (storage.foldername(name))[1] = (
        SELECT company_id::TEXT FROM users WHERE id = auth.uid()
    )
);

-- Policy for job-photos bucket
CREATE POLICY "Job photos access"
ON storage.objects FOR ALL
USING (
    bucket_id = 'job-photos' AND
    auth.uid() IS NOT NULL AND
    (storage.foldername(name))[1] = (
        SELECT company_id::TEXT FROM users WHERE id = auth.uid()
    )
);
```

---

## Step 3: Frontend Setup

### 3.1 Install Dependencies

```bash
cd /home/runner/work/RFE-SAAS/RFE-SAAS
npm install @supabase/supabase-js
```

### 3.2 Create Environment File

Create `.env.local`:

```bash
VITE_SUPABASE_URL=https://sjivzjaktkkqfqmxqvox.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNqaXZ6amFrdGtrcWZxbXhxdm94Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MTU4NDIsImV4cCI6MjA4NjE5MTg0Mn0.F-AWyzwKKZC_bz6CX6QGMA9tX3wyx7t94-HWyHXNXK8
```

### 3.3 Add to .gitignore

Ensure `.env.local` is in `.gitignore`:

```bash
echo ".env.local" >> .gitignore
```

---

## Step 4: Create New Service Files

### 4.1 Create `services/supabase.ts`

```typescript
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL!;
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY!;

export const supabase = createClient(supabaseUrl, supabaseKey);

/**
 * Helper to get current user's company_id
 */
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

/**
 * Helper to get current session
 */
export async function getCurrentSession() {
    const { data: { session } } = await supabase.auth.getSession();
    return session;
}
```

### 4.2 Create `services/auth.ts`

```typescript
import { supabase } from './supabase';
import { UserSession } from '../types';

/**
 * Admin login with email/password
 */
export async function loginUser(
    username: string, 
    password: string
): Promise<UserSession | null> {
    // Try email first, then username
    const loginValue = username.includes('@') ? username : `${username}@temp.local`;
    
    const { data, error } = await supabase.auth.signInWithPassword({
        email: loginValue,
        password: password
    });
    
    if (error || !data.user) {
        throw new Error(error?.message || 'Login failed');
    }
    
    // Get user details
    const { data: userData } = await supabase
        .from('users')
        .select('username, company_id, role')
        .eq('id', data.user.id)
        .single();
    
    // Get company details
    const { data: companyData } = await supabase
        .from('companies')
        .select('company_name')
        .eq('id', userData?.company_id)
        .single();
    
    return {
        username: userData?.username || username,
        companyName: companyData?.company_name || '',
        spreadsheetId: userData?.company_id || '', // Use company_id as spreadsheet_id
        role: userData?.role || 'admin',
        token: data.session.access_token
    };
}

/**
 * Crew login with PIN
 */
export async function loginCrew(
    username: string, 
    pin: string
): Promise<UserSession | null> {
    const { data, error } = await supabase.rpc('crew_login', {
        company_username: username,
        pin: pin
    });
    
    if (error || !data || data.length === 0) {
        throw new Error('Invalid username or PIN');
    }
    
    const crewData = data[0];
    
    if (!crewData.success) {
        throw new Error(crewData.message);
    }
    
    return {
        username: crewData.username,
        companyName: crewData.company_name,
        spreadsheetId: crewData.company_id,
        role: 'crew',
        token: 'crew_session' // Crew doesn't get auth token
    };
}

/**
 * Sign up new company
 */
export async function signupUser(
    username: string,
    password: string,
    companyName: string
): Promise<UserSession | null> {
    const email = username.includes('@') ? username : `${username}@temp.local`;
    
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
    
    if (error || !data.user) {
        throw new Error(error?.message || 'Signup failed');
    }
    
    // Wait a moment for trigger to complete
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Get user details
    const { data: userData } = await supabase
        .from('users')
        .select('username, company_id, role')
        .eq('id', data.user.id)
        .single();
    
    return {
        username: userData?.username || username,
        companyName: companyName,
        spreadsheetId: userData?.company_id || '',
        role: 'admin',
        token: data.session?.access_token || ''
    };
}

/**
 * Sign out
 */
export async function signOut() {
    await supabase.auth.signOut();
}
```

### 4.3 Create `services/database.ts`

```typescript
import { supabase, getUserCompanyId } from './supabase';
import { CalculatorState, EstimateRecord, CustomerProfile } from '../types';

/**
 * Sync down - fetch all data for the company
 */
export async function syncDown(): Promise<Partial<CalculatorState> | null> {
    const companyId = await getUserCompanyId();
    if (!companyId) return null;
    
    try {
        // Fetch all data in parallel
        const [
            { data: settings },
            { data: customers },
            { data: estimates },
            { data: inventory },
            { data: equipment },
            { data: purchaseOrders },
            { data: materialLogs },
            { data: company },
            { data: chemicalStock }
        ] = await Promise.all([
            supabase.from('company_settings').select('*').eq('company_id', companyId),
            supabase.from('customers').select('*').eq('company_id', companyId),
            supabase.from('estimates').select('*').eq('company_id', companyId),
            supabase.from('inventory_items').select('*').eq('company_id', companyId),
            supabase.from('equipment').select('*').eq('company_id', companyId),
            supabase.from('purchase_orders').select('*').eq('company_id', companyId),
            supabase.from('material_logs').select('*').eq('company_id', companyId).order('date', { ascending: false }).limit(100),
            supabase.from('companies').select('*').eq('id', companyId).single(),
            supabase.from('chemical_stock').select('*').eq('company_id', companyId).single()
        ]);
        
        // Transform settings array to object
        const settingsObj: any = {};
        settings?.forEach(s => {
            settingsObj[s.setting_key] = s.setting_value;
        });
        
        // Build warehouse object
        const warehouse = {
            openCellSets: chemicalStock?.open_cell_sets || 0,
            closedCellSets: chemicalStock?.closed_cell_sets || 0,
            items: inventory || []
        };
        
        // Transform company profile
        const companyProfile = {
            companyName: company?.company_name || '',
            addressLine1: company?.address_line1 || '',
            addressLine2: company?.address_line2 || '',
            city: company?.city || '',
            state: company?.state || '',
            zip: company?.zip || '',
            phone: company?.phone || '',
            email: company?.email || '',
            website: company?.website || '',
            logoUrl: company?.logo_url || '',
            crewAccessPin: company?.crew_access_pin || ''
        };
        
        return {
            companyProfile,
            customers: customers || [],
            savedEstimates: estimates || [],
            warehouse,
            equipment: equipment || [],
            purchaseOrders: purchaseOrders || [],
            materialLogs: materialLogs || [],
            lifetimeUsage: {
                openCell: chemicalStock?.lifetime_open_cell_used || 0,
                closedCell: chemicalStock?.lifetime_closed_cell_used || 0
            },
            yields: settingsObj.yields,
            costs: settingsObj.costs,
            expenses: settingsObj.expenses,
            sqFtRates: settingsObj.sqFtRates,
            pricingMode: settingsObj.pricingMode
        };
    } catch (error) {
        console.error('Sync down error:', error);
        return null;
    }
}

/**
 * Sync up - save all data
 */
export async function syncUp(state: CalculatorState): Promise<boolean> {
    const companyId = await getUserCompanyId();
    if (!companyId) return false;
    
    try {
        // Update company profile
        if (state.companyProfile) {
            await supabase
                .from('companies')
                .update({
                    company_name: state.companyProfile.companyName,
                    address_line1: state.companyProfile.addressLine1,
                    address_line2: state.companyProfile.addressLine2,
                    city: state.companyProfile.city,
                    state: state.companyProfile.state,
                    zip: state.companyProfile.zip,
                    phone: state.companyProfile.phone,
                    email: state.companyProfile.email,
                    website: state.companyProfile.website,
                    logo_url: state.companyProfile.logoUrl?.substring(0, 500), // Truncate if too long
                    crew_access_pin: state.companyProfile.crewAccessPin
                })
                .eq('id', companyId);
        }
        
        // Update chemical stock
        if (state.warehouse) {
            await supabase
                .from('chemical_stock')
                .upsert({
                    company_id: companyId,
                    open_cell_sets: state.warehouse.openCellSets,
                    closed_cell_sets: state.warehouse.closedCellSets
                });
        }
        
        // Update settings
        const settingsToUpdate = ['yields', 'costs', 'expenses', 'sqFtRates', 'pricingMode'];
        for (const key of settingsToUpdate) {
            if (state[key as keyof CalculatorState] !== undefined) {
                await supabase
                    .from('company_settings')
                    .upsert({
                        company_id: companyId,
                        setting_key: key,
                        setting_value: state[key as keyof CalculatorState]
                    }, {
                        onConflict: 'company_id,setting_key'
                    });
            }
        }
        
        // Upsert customers
        if (state.customers && state.customers.length > 0) {
            await supabase
                .from('customers')
                .upsert(
                    state.customers.map(c => ({
                        id: c.id,
                        company_id: companyId,
                        name: c.name,
                        address: c.address,
                        city: c.city,
                        state: c.state,
                        zip: c.zip,
                        email: c.email,
                        phone: c.phone,
                        notes: c.notes,
                        status: c.status
                    }))
                );
        }
        
        // Upsert estimates
        if (state.savedEstimates && state.savedEstimates.length > 0) {
            await supabase
                .from('estimates')
                .upsert(
                    state.savedEstimates.map(e => ({
                        id: e.id,
                        company_id: companyId,
                        customer_id: e.customer?.id || null,
                        date: e.date,
                        status: e.status,
                        execution_status: e.executionStatus,
                        inputs: e.inputs,
                        results: e.results,
                        materials: e.materials,
                        expenses: e.expenses,
                        total_value: e.totalValue,
                        pricing_mode: e.pricingMode,
                        sqft_rates: e.sqFtRates,
                        invoice_number: e.invoiceNumber,
                        invoice_date: e.invoiceDate,
                        payment_terms: e.paymentTerms,
                        invoice_lines: e.invoiceLines,
                        scheduled_date: e.scheduledDate,
                        work_order_lines: e.workOrderLines,
                        work_order_sheet_url: e.workOrderSheetUrl,
                        actuals: e.actuals,
                        financials: e.financials,
                        pdf_link: e.pdfLink,
                        site_photos: e.sitePhotos,
                        notes: e.notes,
                        inventory_processed: e.inventoryProcessed
                    }))
                );
        }
        
        // Upsert inventory
        if (state.warehouse?.items && state.warehouse.items.length > 0) {
            await supabase
                .from('inventory_items')
                .upsert(
                    state.warehouse.items.map(i => ({
                        id: i.id,
                        company_id: companyId,
                        name: i.name,
                        quantity: i.quantity,
                        unit: i.unit,
                        unit_cost: i.unitCost || 0
                    }))
                );
        }
        
        // Upsert equipment
        if (state.equipment && state.equipment.length > 0) {
            await supabase
                .from('equipment')
                .upsert(
                    state.equipment.map(e => ({
                        id: e.id,
                        company_id: companyId,
                        name: e.name,
                        status: e.status,
                        last_seen: e.lastSeen
                    }))
                );
        }
        
        return true;
    } catch (error) {
        console.error('Sync up error:', error);
        return false;
    }
}

/**
 * Complete job
 */
export async function completeJob(
    estimateId: string,
    actuals: any
): Promise<boolean> {
    try {
        const { data, error } = await supabase.rpc('process_job_completion', {
            p_estimate_id: estimateId,
            p_actuals: actuals
        });
        
        if (error) throw error;
        
        return data?.success || false;
    } catch (error) {
        console.error('Complete job error:', error);
        return false;
    }
}

/**
 * Mark job as paid
 */
export async function markJobPaid(
    estimateId: string
): Promise<{ success: boolean; estimate?: EstimateRecord }> {
    try {
        const companyId = await getUserCompanyId();
        if (!companyId) return { success: false };
        
        // Get estimate
        const { data: estimate } = await supabase
            .from('estimates')
            .select('*')
            .eq('id', estimateId)
            .single();
        
        if (!estimate) return { success: false };
        
        // Calculate financials
        const { data: financials } = await supabase.rpc('calculate_job_financials', {
            p_estimate_id: estimateId
        });
        
        // Update estimate status and financials
        const { error: updateError } = await supabase
            .from('estimates')
            .update({
                status: 'Paid',
                financials: financials
            })
            .eq('id', estimateId);
        
        if (updateError) throw updateError;
        
        // Insert P&L record
        await supabase
            .from('profit_loss')
            .insert({
                company_id: companyId,
                date_paid: new Date().toISOString().split('T')[0],
                job_id: estimateId,
                customer_name: estimate.inputs?.customerName || '',
                invoice_number: estimate.invoice_number,
                revenue: financials.revenue,
                chemical_cost: financials.chemicalCost,
                labor_cost: financials.laborCost,
                inventory_cost: financials.inventoryCost,
                misc_cost: financials.miscCost,
                total_cogs: financials.totalCOGS,
                net_profit: financials.netProfit,
                margin_percent: financials.margin
            });
        
        return { success: true, estimate: { ...estimate, financials } };
    } catch (error) {
        console.error('Mark job paid error:', error);
        return { success: false };
    }
}

/**
 * Delete estimate
 */
export async function deleteEstimate(estimateId: string): Promise<boolean> {
    try {
        const { error } = await supabase
            .from('estimates')
            .delete()
            .eq('id', estimateId);
        
        return !error;
    } catch (error) {
        console.error('Delete estimate error:', error);
        return false;
    }
}
```

### 4.4 Create `services/storage.ts`

```typescript
import { supabase, getUserCompanyId } from './supabase';

/**
 * Upload PDF to Supabase Storage
 */
export async function uploadPDF(
    fileName: string,
    base64Data: string,
    estimateId?: string
): Promise<string | null> {
    const companyId = await getUserCompanyId();
    if (!companyId) return null;
    
    try {
        // Convert base64 to blob
        const base64String = base64Data.includes(',') 
            ? base64Data.split(',')[1] 
            : base64Data;
        
        const blob = base64ToBlob(base64String, 'application/pdf');
        
        // Upload path
        const path = `${companyId}/${estimateId || 'misc'}/${Date.now()}_${fileName}`;
        
        const { error: uploadError } = await supabase.storage
            .from('company-files')
            .upload(path, blob, {
                contentType: 'application/pdf',
                upsert: false
            });
        
        if (uploadError) throw uploadError;
        
        // Get public URL
        const { data } = supabase.storage
            .from('company-files')
            .getPublicUrl(path);
        
        return data.publicUrl;
    } catch (error) {
        console.error('PDF upload error:', error);
        return null;
    }
}

/**
 * Upload image to Supabase Storage
 */
export async function uploadImage(
    base64Data: string,
    fileName: string = 'image.jpg'
): Promise<string | null> {
    const companyId = await getUserCompanyId();
    if (!companyId) return null;
    
    try {
        const base64String = base64Data.includes(',') 
            ? base64Data.split(',')[1] 
            : base64Data;
        
        const blob = base64ToBlob(base64String, 'image/jpeg');
        
        const timestamp = Date.now();
        const path = `${companyId}/${timestamp}_${fileName}`;
        
        const { error: uploadError } = await supabase.storage
            .from('job-photos')
            .upload(path, blob, {
                contentType: 'image/jpeg'
            });
        
        if (uploadError) throw uploadError;
        
        const { data } = supabase.storage
            .from('job-photos')
            .getPublicUrl(path);
        
        return data.publicUrl;
    } catch (error) {
        console.error('Image upload error:', error);
        return null;
    }
}

/**
 * Convert base64 to Blob
 */
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

## Step 5: Update Existing Files

### 5.1 Update `constants.ts`

Replace the entire file with:

```typescript
// Supabase configuration
export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://sjivzjaktkkqfqmxqvox.supabase.co';
export const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNqaXZ6amFrdGtrcWZxbXhxdm94Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MTU4NDIsImV4cCI6MjA4NjE5MTg0Mn0.F-AWyzwKKZC_bz6CX6QGMA9tX3wyx7t94-HWyHXNXK8';

// Legacy Google Script URL (deprecated)
export const GOOGLE_SCRIPT_URL: string = '';
```

### 5.2 Update `services/api.ts`

Replace all the Google Script API calls with Supabase calls. Import the new service functions:

```typescript
// Import new services
import { loginUser as supabaseLogin, loginCrew as supabaseCrewLogin, signupUser as supabaseSignup } from './auth';
import { syncDown as supabaseSyncDown, syncUp as supabaseSyncUp, completeJob as supabaseCompleteJob, markJobPaid as supabaseMarkJobPaid, deleteEstimate as supabaseDeleteEstimate } from './database';
import { uploadPDF as supabaseUploadPDF, uploadImage as supabaseUploadImage } from './storage';

// Export the Supabase functions
export const loginUser = supabaseLogin;
export const loginCrew = supabaseCrewLogin;
export const signupUser = supabaseSignup;
export const syncDown = supabaseSyncDown;
export const syncUp = supabaseSyncUp;
export const completeJob = supabaseCompleteJob;
export const markJobPaid = supabaseMarkJobPaid;
export const deleteEstimate = supabaseDeleteEstimate;
export const savePdfToDrive = supabaseUploadPDF;
export const uploadImage = supabaseUploadImage;

// Implement remaining functions...
```

---

## Step 6: Testing

### 6.1 Test Authentication

1. Start the dev server: `npm run dev`
2. Navigate to the login page
3. Try signing up a new account
4. Verify the company and user are created in Supabase Dashboard

### 6.2 Test Data Sync

1. Login as admin
2. Create a customer
3. Check Supabase Dashboard to verify customer was created
4. Refresh the page
5. Verify customer data loads correctly

### 6.3 Test Crew Login

1. Get the crew PIN from the companies table
2. Logout and try crew login
3. Verify crew can view jobs but not edit settings

---

## Step 7: Data Migration (Optional)

If you have existing data in Google Sheets:

1. Export all data from Google Sheets
2. Transform to match Supabase schema
3. Use the Supabase SQL Editor to bulk insert
4. Verify data integrity

---

## Step 8: Production Deployment

### 8.1 Environment Variables

Set these in your hosting platform (Vercel/Netlify):

```
VITE_SUPABASE_URL=https://sjivzjaktkkqfqmxqvox.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNqaXZ6amFrdGtrcWZxbXhxdm94Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MTU4NDIsImV4cCI6MjA4NjE5MTg0Mn0.F-AWyzwKKZC_bz6CX6QGMA9tX3wyx7t94-HWyHXNXK8
```

### 8.2 Build and Deploy

```bash
npm run build
# Deploy dist/ folder to your hosting platform
```

---

## Troubleshooting

### Issue: RLS Blocking Queries

**Solution:** Ensure user is authenticated and has company_id set

```sql
SELECT auth.uid(), get_user_company_id();
```

### Issue: Storage Upload Fails

**Solution:** Check bucket policies and ensure user is authenticated

### Issue: Crew Login Not Working

**Solution:** Verify crew_login function exists and PIN is correct

---

## Support

- Supabase Documentation: https://supabase.com/docs
- Supabase Discord: https://discord.supabase.com
- Project Dashboard: https://supabase.com/dashboard/project/sjivzjaktkkqfqmxqvox

---

## Next Steps

1. ✅ Complete database setup
2. ✅ Install frontend dependencies
3. ⏳ Create service files
4. ⏳ Update existing files
5. ⏳ Test authentication
6. ⏳ Test data operations
7. ⏳ Deploy to production

**Estimated Time to Complete:** 4-6 hours for experienced developer
