#test-create-payments.coffee

test           = require 'blue-tape'
Epiquery       = require '../devUtil/lib/epi-request'
Promise        = require 'bluebird' 
invoiceCreator = require '../devUtil/lib/invoice-creator'
moment         = require 'moment' 
_              = require 'lodash' 
util           = require './util'

#exit if environment not setup
if typeof process.env.EPIQUERY_SERVER == 'undefined'
    console.log "Environment variables have not been sourced."
    process.exit() 

epi                                   = new Epiquery {verbose: false}
createDate                            = new moment().subtract(7, 'd') #far enough in the past so assign does something  

sumEntryAmounts = (entries, currencyCode) ->
    return _.reduce entries, (sum,entry) -> 
        return if currencyCode == entry.CURRENCY_CODE then sum + entry.AMOUNT else sum
    , 0

sumEntryUsdAmounts = (entries, currencyCode) ->
    sum = _.reduce entries, (sum,entry) -> 
        return if currencyCode == entry.CURRENCY_CODE then sum + entry.USD_AMOUNT else sum
    , 0 
    return Math.ceil sum

createPayments = (ctx) ->
    return epi.run 'paymentSchema/test/backDateInvoicesForPayment', {}
    .then (results) ->
        return epi.run 'paymentSchema/createPaymentsForApprovedInvoices', {}
    .then (results) ->
        arr = []
        ctx.createPaymentResults = results
        arr.push epi.run 'paymentSchema/test/getInvoices', {}
        arr.push epi.run 'paymentSchema/test/getApprovals', {} 
        arr.push epi.run 'paymentSchema/test/getPayments', {}

        return Promise.all arr
    .then (results) ->
        ctx.invoices        = results[0]
        ctx.assignments     = results[1][0]
        ctx.votes           = results[1][1]
        ctx.payments        = results[2][0]
        ctx.pirs            = results[2][1]
        ctx.dboPayments     = results[2][2]
        ctx.hsbcApprovals   = results[2][3]
        ctx.currencies      = _.uniq _.flatMap ctx.invoiceById, (obj) -> return obj.CURRENCY_COD

        return ctx

preSetup = () ->
    return util.ensureCmInfos()
    .then () ->
        return util.ensureApprovalGroups()
    .then () ->
        return epi.run 'paymentSchema/devUtils/clearAllData', {}
    .then (results) ->
        console.log JSON.stringify results
        return {}
    .catch (err) ->
        throw err

verifyRecordCounts = (ctx,invoiceCount,paymentCount,paymentInvoiceRelationCount,dboPaymentCount,hsbcApprovedCount) ->
    ctx.assert.equal ctx.invoices.length, invoiceCount, "invoice count"
    ctx.assert.equal ctx.payments.length, paymentCount, "payment count"
    ctx.assert.equal ctx.pirs.length, paymentInvoiceRelationCount, "payment/invoice relation count"
    ctx.assert.equal ctx.dboPayments.length, dboPaymentCount, "dbo payment count"
    ctx.assert.equal ctx.hsbcApprovals.length, hsbcApprovedCount, "hsbc approved count"


setupTestInvoices = (ctx) ->
    return epi.run 'paymentSchema/test/setupTestInvoices', ctx.setup
    .then () ->
        return ctx
    .catch (err) ->
        throw err

verifyCommon = (ctx,skipPir) ->
    paymentIds          = _.uniq _.flatMap ctx.payments, (payment) -> payment.PAYMENT_ID
    pirPaymentIds       = _.uniq _.flatMap ctx.pirs, (pir) -> pir.PAYMENT_ID

    invoiceIds          = _.uniq _.flatMap ctx.invoices, (invoice) -> invoice.INVOICE_ID
    pirInvoiceIds       = _.uniq _.flatMap ctx.pirs, (pir) -> pir.INVOICE_ID

    dboPaymentIds       = _.uniq _.flatMap ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID']
    dboPaymentOldIds    = _.uniq _.flatMap ctx.dboPayments, (dboPayment) -> dboPayment.PAYMENT_ID
    hsbcApprovalsOldIds = _.uniq _.flatMap ctx.hsbcApprovals, (hsbcApproval) -> hsbcApproval.PAYMENT_ID

    ctx.assert.equal _.difference(paymentIds, pirPaymentIds).length, 0, "all payments in relation"
    if !skipPir or !skipPir then ctx.assert.equal _.difference(invoiceIds, pirInvoiceIds).length, 0, "all invoices in relation"
    ctx.assert.equal _.difference(dboPaymentIds, paymentIds).length, 0, "all payments have a dbo payment"
    ctx.assert.equal _.difference(dboPaymentOldIds, hsbcApprovalsOldIds).length, 0, "all dbo payments are HSBC approved"

    verifyInvoicePaymentAmounts ctx

verifyInvoicePaymentAmounts = (ctx) ->
    _.forEach ctx.cmInfos, (cmInfo) ->
        _.forEach ctx.currencies, (currency) ->
            invoiceSum    = sumEntryAmounts invoiceByPersonId[cmInfo.PERSON_ID], currency
            paymentSum    = sumEntryAmounts paymentByPersonId[cmInfo.PERSON_ID], currency
            ctx.assert.equal -1*paymentSum, invoiceSum, "invoice amount = payment amount #{currency} for person ID #{cmInfo.PERSON_ID}"

verifyDboPaymentPersonAccountAndAmount = (ctx,dboPayment,personId,paymentAccountId,usdAmount) ->
    ctx.assert.equal dboPayment.PAYMENT_ACCOUNT_ID, paymentAccountId , "dbo payment payment account ID"
    ctx.assert.equal dboPayment.PAYMENT, usdAmount, "dbo payment amount"
    ctx.assert.equal dboPayment.PERSON_ID, personId, "dbo payment person ID"

setupCpOverride = (ctx) ->
    return epi.run 'paymentSchema/test/setupCpOverride', ctx.override
    .then (results) ->
        ctx.cpId     = results[0].CONSULTATION_PARTICIPANT_ID
        ctx.personId = results[0].PERSON_ID
        return ctx 

#=================================TESTS=================================

# you can do 'test.only' to only run a specific test -- as for debugging

test 'worksWithNothing', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()
        .then () ->
            ctx = {assert:assert}
            return createPayments(ctx)
        .then (ctx) ->
            verifyRecordCounts(ctx,0,0,0,0,0) #inv,pay,pir,dboPay,hsdcApproved            
            resolve()
        .catch (err) ->
            reject err

test 'ignoresPendingApproval', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()
        .then () -> 
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]

            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,1,0,0,0,0) #inv,pay,pir,dboPay,hsdcApproved           
            resolve()
        .catch (err) ->
            reject err
   
test 'ignoresPartialApproval', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()
        .then () -> 
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]

            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Events'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Events',grantedInd:1,personId:util.getAccountingPersonId 0} 
            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,1,0,0,0,0) #inv,pay,pir,dboPay,hsdcApproved           
            resolve()
        .catch (err) ->
            reject err

test 'ignoresRejected', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()
        .then () ->
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]
            personId = ctx.cmInfos[0].PERSON_ID

            # two assignments, one reject vote, one accept vote
            index = 0
            setup.entries.push {personId:personId,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Events'}            
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Events',grantedInd:1,personId:util.getEventsPersonId 0} 
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:0,personId:util.getAccountingPersonId 0} 

            # two assignments, one reject vote, two accept votes 
            # the two accept votes can happend if two people vote on the same--the reject vote 'wins'
            index++
            setup.entries.push {personId:personId,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Events'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Events',grantedInd:1,personId:util.getEventsPersonId 0} 

            # TODO: is this ok? first one wins
            # or do we want to include the person in the primary key and allow multiples votes per group
            # (when we check the count of approve ones we do ask for unique approval group to avoid double counint
            # for rejects its different--is anyone rejects its rejected)
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:0,personId:util.getAccountingPersonId 1}             
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 


            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,2,0,0,0,0) #inv,pay,pir,dboPay,hsdcApproved           
            resolve()
        .catch (err) ->
            reject err

test 'multipleCmsOneInvoiceEach', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()            
        .then () -> 
            ctx = {}
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),2)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]

            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:111}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:ctx.cmInfos[1].PERSON_ID,currencyCode:'USD',amount:222}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}                      

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,2,2,2,2,2) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx 

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment.COUNCIL_MEMBER_ID == ctx.cmInfos[0].COUNCIL_MEMBER_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,111

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment.COUNCIL_MEMBER_ID == ctx.cmInfos[1].COUNCIL_MEMBER_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[1].PERSON_ID,ctx.cmInfos[1].PROJECT_PAYMENT_ACCOUNT_ID,222   

            resolve()         
        .catch (err) ->
            reject err

test 'oneCmMultipleInvoicesSingleCurrency', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()
        .then () -> 
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]
            personId = ctx.cmInfos[0].PERSON_ID

            index = 0
            setup.entries.push {personId:personId,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}  

            index++
            setup.entries.push {personId:personId,currencyCode:'USD',amount:200}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}        

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,2,1,2,1,1) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx 

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment.COUNCIL_MEMBER_ID == ctx.cmInfos[0].COUNCIL_MEMBER_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,300
                     
            resolve()
        .catch (err) ->
            reject err

test 'oneCmMultipleInvoicesMultipleCurrencies', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()
        .then () -> 
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]
            personId = ctx.cmInfos[0].PERSON_ID
            
            index = 0
            setup.entries.push {personId:personId,currencyCode:'EUR',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:personId,currencyCode:'EUR',amount:200}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++ 
            setup.entries.push {personId:personId,currencyCode:'HKD',amount:300}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}            
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:personId,currencyCode:'HKD',amount:400}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}            
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}           

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx                    
        .then (ctx) ->
            verifyRecordCounts ctx,4,2,4,2,2 #inv,pay,pir,dboPay,hsdcApproved 
            verifyCommon ctx 

            payment    = _.find ctx.payments, (payment) -> payment.CURRENCY_CODE == 'EUR'
            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == payment.PAYMENT_ID
            ctx.assert.equal dboPayment.PAYMENT, sumEntryUsdAmounts(ctx.invoices,'EUR'), "USD for EUR on dbo payment"

            payment    = _.find ctx.payments, (payment) -> payment.CURRENCY_CODE == 'HKD'
            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == payment.PAYMENT_ID
            ctx.assert.equal dboPayment.PAYMENT, sumEntryUsdAmounts(ctx.invoices,'HKD'), "USD for HKD on dbo payment"
          
            resolve()
        .catch (err) ->
            reject err

test 'doesNotPayInvoiceTwice', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()            
        .then () -> 
            ctx = {}
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]

            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:111}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 
            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,1,1,1,1,1) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx 

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment.COUNCIL_MEMBER_ID == ctx.cmInfos[0].COUNCIL_MEMBER_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,111

            #run create payments again
            ctx = assert:ctx.assert,cmInfos:ctx.cmInfos
            return createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,1,1,1,1,1) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx 

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment.COUNCIL_MEMBER_ID == ctx.cmInfos[0].COUNCIL_MEMBER_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,111
      
            resolve()         
        .catch (err) ->
            reject err

test 'cmWithProjectAndExpensePaymentAccountTheSameDoesNotCombineProjectAndExpensePayments', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()            
        .then () -> 
            ctx = {}
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]

            # 1 project invoice
            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            # 3 expense invoices - 1 USD and 2 HKD
            index++
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:200}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'HKD',amount:1000}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'HKD',amount:2000}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}             

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,4,3,4,3,3) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx

            #verifies project and usd expense payments are NOT lumped together 

            arr = _.partition ctx.payments, (payment) -> return payment.CURRENCY_CODE == 'USD'
            usdPayments = arr[0]
            hkdPayments = arr[1]

            pirsByPaymentId = _.keyBy ctx.pirs, (pir) -> return pir.PAYMENT_ID
            arr = _.partition usdPayments, (payment) -> return pirsByPaymentId[payment.PAYMENT_ID].EXPENSE_OR_PROJECT == 'PROJECT'
            usdProjectPayment = arr[0][0]
            usdExpensePayment = arr[1][0]

            ctx.assert.equal usdPayments.length, 2, "usd payment record count"
            ctx.assert.equal hkdPayments.length, 1, "hkd payment record count"

            ctx.assert.equal usdProjectPayment.AMOUNT,   -100,  "usd project payment amount"
            ctx.assert.equal usdExpensePayment.AMOUNT,   -200,  "usd expense payment amount"
            ctx.assert.equal hkdPayments[0].AMOUNT,      -3000, "hkd payment amount"

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == usdProjectPayment.PAYMENT_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,100

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == usdExpensePayment.PAYMENT_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,200            

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == hkdPayments[0].PAYMENT_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID, sumEntryUsdAmounts ctx.invoices, 'HKD'          

            resolve()         
        .catch (err) ->
            reject err

test 'cmWithDistinctProjectAndExpensePaymentAccounts', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()            
        .then () -> 
            ctx = {}
            ctx = assert:assert,cmInfos:_.take(util.getCmsWithDistinctExpensePaymentAccounts(),1)
            setup = entries:[],invoices:[],expenses:[],assignments:[],votes:[]

            assert.ok ctx.cmInfos.length > 0, "Have CM with distinct expense account for this test"

            # 1 project invoice
            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:100}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            # 3 expense invoices - 1 USD and 2 HKD
            index++
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:200}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'HKD',amount:1000}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            index++
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'HKD',amount:2000}
            setup.invoices.push {entryIndex:index}
            setup.expenses.push {invoiceIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}             

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,4,3,4,3,3) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx

            #verifies project and usd expense payments are NOT lumped together 

            arr = _.partition ctx.payments, (payment) -> return payment.CURRENCY_CODE == 'USD'
            usdPayments = arr[0]
            hkdPayments = arr[1]

            pirsByPaymentId = _.keyBy ctx.pirs, (pir) -> return pir.PAYMENT_ID
            arr = _.partition usdPayments, (payment) -> return pirsByPaymentId[payment.PAYMENT_ID].EXPENSE_OR_PROJECT == 'PROJECT'
            usdProjectPayment = arr[0][0]
            usdExpensePayment = arr[1][0]

            ctx.assert.equal usdPayments.length, 2, "usd payment record count"
            ctx.assert.equal hkdPayments.length, 1, "hkd payment record count"

            ctx.assert.equal usdProjectPayment.AMOUNT,   -100,  "usd project payment amount"
            ctx.assert.equal usdExpensePayment.AMOUNT,   -200,  "usd expense payment amount"
            ctx.assert.equal hkdPayments[0].AMOUNT,      -3000, "hkd payment amount"

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == usdProjectPayment.PAYMENT_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].PROJECT_PAYMENT_ACCOUNT_ID,100

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == usdExpensePayment.PAYMENT_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].EXPENSE_PAYMENT_ACCOUNT_ID,200            

            dboPayment = _.find ctx.dboPayments, (dboPayment) -> dboPayment['PAYMENT.PAYMENT_ID'] == hkdPayments[0].PAYMENT_ID
            verifyDboPaymentPersonAccountAndAmount ctx,dboPayment,ctx.cmInfos[0].PERSON_ID,ctx.cmInfos[0].EXPENSE_PAYMENT_ACCOUNT_ID, sumEntryUsdAmounts ctx.invoices, 'HKD'          

            resolve()         
        .catch (err) ->
            reject err       

test 'consultationAdjustment', (assert) ->
    return new Promise (resolve, reject) ->
        ctx = { assert:assert }
        preSetup()
        .then () ->
            return util.ensureGlgPersonId()
        .then (glgPersonId) ->    
            # create dbo.duration_override
            ctx.override =
                meetingMinutes:45
                prepMinutes:null
                minProjectAmount:null
                markedDownRate:200
                durationOverrideMinutes:60 # that's 15 minutes more
                glgPersonId:glgPersonId

            return setupCpOverride ctx
        .then () ->
            # create consultation
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:150}
            setup.invoices.push {entryIndex:index}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            ctx.setup = setup
            return setupTestInvoices ctx 
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            ctx.assert.ok results, "createAdjustments db results: #{JSON.stringify results}"
            ctx.assert.equal results.length, 1, "adjustment count"
            return createPayments ctx
        .then () ->
            verifyRecordCounts(ctx,2,1,2,1,1) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx  
            ctx.assert.equal ctx.dboPayments[0].PAYMENT, 200, "dboPayment amount"

            resolve()
        .catch (err) ->
            reject err    
        
test 'skipsCmsWithNoPaymentAccount', (assert) ->
    return new Promise (resolve, reject) ->
        preSetup()            
        .then () ->
            return epi.run 'paymentSchema/test/getCmInfoForCmWithNoPaymentAccount', {howMany:1}
        .then (results) ->
            ctx = {assert:assert,cmInfos:[]}
            ctx.cmInfos.push results[0]                                            # this cm has no payment account
            ctx.cmInfos.push _.take(util.getCmsWithSinglePaymentAccount(),1)[0]    # this one does
            setup = entries:[],invoices:[],assignments:[],votes:[]

            # create an appoved invoice for the cm with no payment account
            index = 0
            setup.entries.push {personId:ctx.cmInfos[0].PERSON_ID,currencyCode:'USD',amount:111}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0} 

            # create an appoved invoice for the cm with a payment account
            index++
            setup.entries.push {personId:ctx.cmInfos[1].PERSON_ID,currencyCode:'USD',amount:222}
            setup.invoices.push {entryIndex:index}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Accounting',grantedInd:1,personId:util.getAccountingPersonId 0}             

            ctx.setup = setup
            return setupTestInvoices ctx                     
        .then (ctx) ->
            createPayments ctx
        .then (ctx) ->
            verifyRecordCounts(ctx,2,1,1,1,1) #inv,pay,pir,dboPay,hsdcApproved
            verifyCommon ctx, true #skipPir
            assert.equal ctx.createPaymentResults.length, 1
            assert.ok ctx.createPaymentResults[0].message.includes 'Payment account not found', 'contains error message'

            resolve()         
        .catch (err) ->
            reject err