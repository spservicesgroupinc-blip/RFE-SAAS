# 🚀 RFE Foam Pro - Supabase Migration Quick Reference

## 📌 Supabase Project Credentials

```
Project URL:     https://sjivzjaktkkqfqmxqvox.supabase.co
Anon Key:        eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Dashboard:       https://supabase.com/dashboard/project/sjivzjaktkkqfqmxqvox
```

## ⚡ Quick Start (5 Steps)

### 1️⃣ Database Setup
```sql
-- In Supabase SQL Editor, run:
migration/schema.sql
```

### 2️⃣ Storage Buckets
```
Create two buckets:
- company-files (for PDFs)
- job-photos (for images)
```

### 3️⃣ Install Dependencies
```bash
npm install @supabase/supabase-js
```

### 4️⃣ Environment Variables
```bash
# Create .env.local
VITE_SUPABASE_URL=https://sjivzjaktkkqfqmxqvox.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 5️⃣ Create Service Files
```
services/supabase.ts
services/auth.ts
services/database.ts
services/storage.ts
```

## 📚 Documentation Files

| File | Purpose | Size |
|------|---------|------|
| `SUPABASE_MIGRATION_PLAN.md` | Complete strategy | 32KB |
| `migration/schema.sql` | Database schema | 31KB |
| `migration/IMPLEMENTATION_GUIDE.md` | Step-by-step guide | 26KB |
| `migration/README.md` | Overview | 6KB |

## 🗄️ Database Tables (14 Total)

```
Core Tables:
✓ companies          - Tenant root
✓ users              - Authentication  
✓ company_settings   - Config key-value store
✓ customers          - CRM
✓ estimates          - Jobs/Invoices (main entity)

Inventory:
✓ inventory_items    - General supplies
✓ chemical_stock     - Foam tanks
✓ equipment          - Tools/assets

Operations:
✓ estimate_items     - Line items
✓ purchase_orders    - Material orders
✓ material_logs      - Usage audit trail
✓ time_logs          - Crew time tracking
✓ profit_loss        - Financial reports
✓ trial_memberships  - Lead capture
```

## 🔐 Security Features

- ✅ Row Level Security (RLS) on all tables
- ✅ Multi-tenant isolation by company_id
- ✅ Supabase Auth integration
- ✅ Custom crew PIN authentication
- ✅ Storage bucket policies

## 🔄 API Migration Map

| Old (Google Script) | New (Supabase) |
|---------------------|----------------|
| `LOGIN` | `supabase.auth.signInWithPassword()` |
| `SIGNUP` | `supabase.auth.signUp()` |
| `CREW_LOGIN` | `supabase.rpc('crew_login')` |
| `SYNC_DOWN` | `supabase.from().select()` (parallel) |
| `SYNC_UP` | `supabase.from().upsert()` (batch) |
| `COMPLETE_JOB` | `supabase.rpc('process_job_completion')` |
| `MARK_JOB_PAID` | `supabase.rpc('calculate_job_financials')` |
| `SAVE_PDF` | `supabase.storage.upload()` |
| `UPLOAD_IMAGE` | `supabase.storage.upload()` |

## 🛠️ Key Database Functions

```sql
-- Helper for RLS
get_user_company_id() → UUID

-- Crew authentication  
crew_login(username, pin) → session_data

-- Job completion with transactions
process_job_completion(estimate_id, actuals) → result

-- P&L calculation
calculate_job_financials(estimate_id) → financials
```

## 📊 Data Flow

```
Admin Dashboard → Supabase Client → RLS Check → Company Data
Crew App       → crew_login()    → RLS Check → Job Data
File Upload    → Storage API     → Bucket Policy → Company Folder
```

## ⚠️ Critical Changes from Google Script

### 1. Concurrency Handling
**Old:** LockService in Google Script  
**New:** PostgreSQL transactions (automatic)

### 2. Image Storage
**Old:** Base64 in spreadsheet cells  
**New:** Upload to Storage, store URL only

### 3. Query Performance
**Old:** Frontend array filtering  
**New:** SQL WHERE clauses on server

### 4. Authentication
**Old:** Manual password hashing, token generation  
**New:** Supabase Auth handles everything

## 🎯 Testing Checklist

```
□ Run schema.sql successfully
□ Create storage buckets
□ Test admin signup/login
□ Test crew PIN login
□ Create customer (verify RLS)
□ Create estimate
□ Complete job (verify transactions)
□ Upload PDF
□ Upload image
□ Mark job paid (verify P&L)
□ Multi-tenant isolation test
```

## 📈 Performance Optimizations

- ✓ Comprehensive indexing
- ✓ Parallel query execution
- ✓ JSONB for flexible schemas
- ✓ Connection pooling (automatic)
- ✓ CDN for storage (automatic)

## 💰 Costs (Supabase Pro Plan)

```
$25/month includes:
- 8GB database
- 100GB bandwidth
- 50GB storage
- Daily backups
- Point-in-time recovery

Suitable for: 10-50 companies
```

## 🐛 Common Issues & Solutions

### Issue: RLS blocking queries
```sql
-- Check authentication
SELECT auth.uid(), get_user_company_id();
```

### Issue: Storage upload fails
```
Verify bucket exists and user is authenticated
Check bucket policy allows upload
```

### Issue: Crew login not working
```sql
-- Verify function exists
SELECT * FROM pg_proc WHERE proname = 'crew_login';

-- Test directly
SELECT * FROM crew_login('admin_username', '1234');
```

## 📞 Support

- Docs: https://supabase.com/docs
- Discord: https://discord.supabase.com
- Dashboard: https://supabase.com/dashboard/project/sjivzjaktkkqfqmxqvox

## 🎓 Learning Resources

1. Start with `migration/IMPLEMENTATION_GUIDE.md`
2. Review `SUPABASE_MIGRATION_PLAN.md` for architecture
3. Reference `migration/schema.sql` for schema details
4. Check `migration/README.md` for overview

## ⏱️ Estimated Timeline

```
Database Setup:     1-2 hours
Service Files:      2-3 hours  
Testing:            2-3 hours
Deployment:         1 hour

Total:              6-9 hours
```

## ✅ Success Criteria

Migration complete when:
- All features work in new system
- Multi-tenant isolation verified
- Performance equal or better
- All data migrated
- Security policies working
- No data loss

---

**Version:** 1.0  
**Last Updated:** 2026-02-09  
**Status:** ✅ Ready for Implementation

## 🔗 Quick Links

- [Full Migration Plan](./SUPABASE_MIGRATION_PLAN.md)
- [Implementation Guide](./migration/IMPLEMENTATION_GUIDE.md)
- [Database Schema](./migration/schema.sql)
- [Migration Overview](./migration/README.md)
