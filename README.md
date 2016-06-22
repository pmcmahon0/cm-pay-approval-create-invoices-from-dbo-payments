# cm-pay-approval
Single page app for approving payment of project and expense reimbursement invoices submitted through the [cm-pay](https://github.com/glg/cm-pay) app.

The cm-pay-approval app replaces the Vega payment approval screens in [GLGRFinance](https://github.com/GLGFinance/GLGRFinance). In the short-term it will be used in parallel with the Vega screens, as both the workflow and supporting database tables of each differ. In Vega, a single dbo.payment record is used to capture a payment request, payment approvals, and the actual payment to the bank; tables in the new `payment` schema in GLGLIVE separate these concerns. A payment request in Vega is approved by a chain of approval users, sequentially; in the new workflow approval occurs in parallel. In time the new workflow will also support automated approval.


#### Install

```
npm install
bower install
```

#### Serve

For development, you can serve the app with the built-in HTTP server that Python provides. Download [Python](https://www.python.org/download/releases/2.7.5/), install it globally, and then run

```
python -m SimpleHTTPServer
```
in the repo root. Browse to `http://localhost:8000/` and click on the `src` folder.

#### Vulcanize

To run under Starphleet we vulcanize the files into `public/index.html`. This is done by:

```
npm run postinstall
```
In production, the vulcanize step is run automatically after autodeployment.


#### Tests

There are no automated tests of the UI itself. However, this repo contains several tests of the SQL logic that assigns invoices to various GLG approval groups, creates adjustment invoices for price overrides, and creates payments. Approval assignment and invoice adjustments for price overrides are cron jobs; the creation of payments occurs during daily Payment Processor runs.  

```
source ./devUtil/dev.env
npm run test-assign-invoices
npm run test-create-adjustments
npm run test-create-payments
```
*** Note: Only run these tests in a local development environment becuase they will delete all data from the payment schema tables prior to setting up each test. ***

#### Development Utility

The `devUtil` folder has a script you can use to create invoices for testing.

```
sh run.sh
```
