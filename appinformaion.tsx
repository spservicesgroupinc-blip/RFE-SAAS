This is a comprehensive specification for migrating RFE Foam Pro from a client-side/Google Apps Script prototype to a production-ready SaaS architecture.
Since Google Apps Script cannot handle high-concurrency SaaS workloads, we will architect this using a standard RESTful API (Node.js/Python/Go) backed by a Relational Database (PostgreSQL is recommended due to the financial and inventory transactional nature).
1. High-Level Architecture
Frontend: Existing React PWA (Hosted on Vercel/Netlify/AWS S3).
Backend API: Node.js (Express/NestJS) or Python (FastAPI).
Database: PostgreSQL (with JSONB support for complex calculation inputs).
Object Storage: AWS S3 or Google Cloud Storage (for images and generated PDFs).
Authentication: Auth0, Firebase Auth, or AWS Cognito (Multi-tenant support required).
2. Database Schema & Data Points
Here is the breakdown of tables and fields required to support the TypeScript interfaces found in your code (types.ts).
A. Tenants & Authentication (SaaS Layer)
1. Companies (Tenants)
id (UUID, Primary Key)
name (String)
subscription_status (Enum: Trial, Active, PastDue)
created_at (Timestamp)
crew_access_pin (Hashed String) - Used for Crew Login flow
Settings / Profile Data:
address_line_1
address_line_2
city, state, zip
phone, email, website
logo_url (S3 URL)
2. Users
id (UUID, PK)
company_id (Foreign Key -> Companies)
email (String, Unique)
password_hash (String)
role (Enum: Admin, Manager, Crew)
full_name (String)
B. Configuration & Pricing (Settings)
3. Global_Configs (One row per company)
company_id (FK)
Material Costs:
cost_open_cell (Decimal)
cost_closed_cell (Decimal)
labor_rate_hourly (Decimal)
Yields & Machinery:
yield_open_cell (Int)
yield_closed_cell (Int)
strokes_per_set_oc (Int)
strokes_per_set_cc (Int)
Pricing Strategy:
pricing_mode (Enum: Level_Pricing, SqFt_Pricing)
sqft_rate_wall (Decimal)
sqft_rate_roof (Decimal)
C. CRM & Jobs
4. Customers
id (UUID, PK)
company_id (FK)
name (String)
address, city, state, zip
email, phone
notes (Text)
status (Enum: Active, Archived, Lead)
5. Estimates (Jobs)
id (UUID, PK)
company_id (FK)
customer_id (FK -> Customers)
estimate_number (String/Sequence)
invoice_number (String, Nullable)
status (Enum: Draft, Work Order, Invoiced, Paid, Archived)
execution_status (Enum: Not Started, In Progress, Completed)
date_created (Timestamp)
date_scheduled (Date, Nullable)
date_invoiced (Date, Nullable)
Financial Snapshots (Locked at time of save):
total_contract_value (Decimal)
total_material_cost (Decimal)
total_labor_cost (Decimal)
margin_percent (Decimal)
Calculation Inputs (JSONB Column):
Stores length, width, wallHeight, roofPitch, isMetalSurface, includeGables, wallSettings (type/thickness), roofSettings (type/thickness), and additionalAreas array.
Notes:
job_notes (Text) - Instructions for crew.
6. Estimate_Items (Line Items)
id (UUID, PK)
estimate_id (FK)
type (Enum: Material, Labor, Fee, Custom)
description (String)
quantity (Decimal)
unit_price (Decimal)
total_amount (Decimal)
D. Inventory & Warehouse
7. Inventory_Items (General Supplies)
id (UUID, PK)
company_id (FK)
name (String)
unit (String)
cost_per_unit (Decimal)
quantity_on_hand (Decimal)
reorder_point (Int)
8. Chemical_Stock (The "Tanks")
company_id (FK)
open_cell_sets (Decimal)
closed_cell_sets (Decimal)
lifetime_open_cell_used (Decimal)
lifetime_closed_cell_used (Decimal)
9. Material_Logs (Audit Trail)
id (UUID, PK)
company_id (FK)
job_id (FK, Nullable)
user_id (FK)
action (Enum: Adjustment, Usage, Restock)
material_type (Enum: OpenCell, ClosedCell, InventoryItem)
quantity_change (Decimal) - Negative for usage, positive for restock.
timestamp (Timestamp)
10. Purchase_Orders
id (UUID, PK)
company_id (FK)
vendor_name (String)
status (Enum: Draft, Sent, Received)
total_cost (Decimal)
items_json (JSONB) - Snapshot of items ordered.
E. Assets
11. Equipment
id (UUID, PK)
company_id (FK)
name (String)
status (Enum: Available, In Use, Maintenance, Lost)
last_seen_job_id (FK -> Estimates, Nullable)
last_seen_date (Timestamp)
F. Crew Operations
12. Time_Logs
id (UUID, PK)
estimate_id (FK)
user_id (FK) or crew_name (String)
start_time (Timestamp)
end_time (Timestamp)
duration_hours (Decimal)
3. Application Functions & Logic to Sync
These functions currently exist in api.ts or Calculator.tsx. Here is how they map to backend endpoints.
Authentication
POST /auth/login: Validate username/password, return JWT.
POST /auth/crew-login: Validate Company ID + PIN, return restricted JWT.
Dashboard & Sync
GET /sync:
Input: Company ID (from Token).
Output: Returns comprehensive JSON object (Customers, Active Estimates, Warehouse Status, Equipment) to hydrate the React Context on load.
Optimization: Implement last_sync_timestamp to only fetch delta changes.
Estimation Engine
POST /estimates (Create/Update):
Receives CalculationState.
Backend Logic:
Save inputs to Estimates table.
Parse materials array and create/update Estimate_Items.
Update financials columns for reporting.
DELETE /estimates/:id: Soft delete the record.
Job Workflow
POST /estimates/:id/status:
Update status (e.g., Draft -> Work Order).
If moving to Work Order: Trigger logic to "Reserve" inventory (optional advanced feature).
If moving to Invoiced: Lock financial snapshots.
If moving to Paid: Trigger P&L finalization.
Inventory Logic
POST /inventory/adjust:
Used for manual warehouse updates.
Updates Inventory_Items or Chemical_Stock.
Writes to Material_Logs.
POST /jobs/:id/complete (The "Crew Submit" function):
Input: actuals object (OC sets, CC sets, Labor hours, Inventory used).
Backend Logic:
Update Estimates with actuals.
Deduct from Chemical_Stock and Inventory_Items.
Increment lifetime_usage in Chemical_Stock.
Create Material_Logs entries for every item used.
Update Equipment location based on job.
Equipment
POST /equipment: CRUD for tools.
PATCH /equipment/:id/location: Update last_seen data (called when generating Work Order or completing job).
Files
POST /upload/image:
Accepts multipart/form-data.
Uploads to AWS S3.
Returns public URL.
POST /upload/pdf:
Uploads generated PDF blob to S3.
Associates URL with Estimate record.
4. Critical Logic Changes from App Script
Concurrency: The current app relies on LockService in Google Script to prevent race conditions during inventory updates. In a real DB, you must use Database Transactions (BEGIN/COMMIT) when deducting inventory to ensure two crews don't use the same stock simultaneously causing negative integers or calculation errors.
Image Handling: The current app tries to pass Base64 strings. The new backend must upload images to S3/Cloud Storage immediately and only store the URL string in the database.
Search/Filtering: Currently, the frontend filters arrays. With a real backend, dashboard queries (like "Show me all Unpaid Invoices") should be SQL queries executed on the server for performance (SELECT * FROM estimates WHERE status = 'Invoiced').
5. Production Tech Stack Recommendation
Database: PostgreSQL (Managed via Supabase or AWS RDS).
Backend: Node.js with Prisma ORM (Typescript). Prisma mirrors your frontend Typescript interfaces perfectly, making the migration of types.ts very easy.
File Storage: AWS S3.
Hosting: Vercel (Frontend) + Railway/Render (Backend).
