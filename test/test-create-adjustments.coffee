#test-create-adjustments.coffee

test           = require 'blue-tape'
Epiquery       = require '../devUtil/lib/epi-request'
Promise        = require 'bluebird' 
invoiceCreator = require '../devUtil/lib/invoice-creator'
moment         = require 'moment' 
_              = require 'lodash' 
util           = require './util'
epi            = new Epiquery {verbose: false}

setupTest = (ctx) ->
    return epi.run 'paymentSchema/devUtils/clearAllData', {}
    .then (results) ->
        return util.ensureApprovalGroups()
    .then (results) ->
        return util.ensureGlgPersonId()
    .then (id) ->
        ctx.glgPersonId = id
        data = 
            meetingMinutes:ctx.meetingMinutes
            prepMinutes:ctx.prepMinutes
            minProjectAmount:ctx.minProjectAmount
            markedDownRate:ctx.markedDownRate
            durationOverrideMinutes:ctx.durationOverrideMinutes
            glgPersonId:ctx.glgPersonId

        return epi.run 'paymentSchema/test/setupCpOverride', data
    .then (results) ->
        if !results or results.length <= 0
            throw new Error 'setupCpOverride failed'
        ctx.cpId = results[0].CONSULTATION_PARTICIPANT_ID
        ctx.personId = results[0].PERSON_ID
        return ctx
   
calcAmount = (ctx) ->
    ctx.assert.ok ctx.meetingMinutes
    ctx.assert.ok ctx.markedDownRate

    minutes = ctx.meetingMinutes
    if ctx.prepMinutes
        minutes += ctx.prepMinutes
    return minutes/60 * ctx.markedDownRate 

calcAmountOrMin = (ctx) ->
    amount = calcAmount ctx
    if ctx.minProjectAmount and amount < ctx.minProjectAmount
        return ctx.minProjectAmount
    return amount

#=================================TESTS=================================

# you can do 'test.only' to only run a specific test -- as for debugging

test 'ignoreWhenNoProjectInvoice', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:null
            markedDownRate:200
            durationOverrideMinutes:100 #that's 40 more minutes

        setupTest ctx
        .then (ctx) ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            ctx.assert.ok results, "createAdjustments db results"
            ctx.assert.equal results.length, 0, "adjustment count"
            resolve()
        .catch (err) ->
            reject err

test 'ignoreWhenProjectInvoiceRejected', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:null
            markedDownRate:200
            durationOverrideMinutes:100 #that's 40 more minutes

        ctx.invoiceAmount = calcAmountOrMin ctx

        setupTest ctx
        .then (ctx) ->
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:ctx.invoiceAmount}
            setup.invoices.push {entryIndex:index}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Events'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Events',grantedInd:0,personId:util.getAccountingPersonId 0} 

            return epi.run 'paymentSchema/test/setupTestInvoices', setup
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            ctx.assert.ok results, "createAdjustments db results"
            ctx.assert.equal results.length, 0, "adjustment count"
            resolve()
        .catch (err) ->
            reject err  

test 'ignoreWhenUnderMinimumWaitTime', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:400
            markedDownRate:200
            durationOverrideMinutes:90 #that's $300, under the $400 minimum

        ctx.invoiceAmount = calcAmountOrMin ctx
        setupTest ctx
        .then (ctx) ->
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:ctx.invoiceAmount}
            setup.invoices.push {entryIndex:index}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Accounting'}
            setup.assignments.push {invoiceIndex:index,approvalGroup:'Events'}
            setup.votes.push {invoiceIndex:index,approvalGroup:'Events',grantedInd:1,personId:util.getAccountingPersonId 0} 

            return epi.run 'paymentSchema/test/setupTestInvoices', setup
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            ctx.assert.ok results, "createAdjustments db results"
            ctx.assert.equal results.length, 0, "adjustment count"
            resolve()
        .catch (err) ->
            reject err 

test 'ignoreNegativeAdjustment', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:null
            markedDownRate:200
            durationOverrideMinutes:50 # that's 10 less minutes

        ctx.invoiceAmount = calcAmountOrMin ctx
        
        setupTest ctx
        .then (ctx) ->
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:ctx.invoiceAmount}
            setup.invoices.push {entryIndex:index}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}

            return epi.run 'paymentSchema/test/setupTestInvoices', setup
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            ctx.assert.ok results, "createAdjustments db results"
            ctx.assert.equal results.length, 0, "adjustment count"
            resolve()
        .catch (err) ->
            reject err 

test 'adjustWhenProjectInvoiceNotRejected', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:200
            markedDownRate:200
            durationOverrideMinutes:90
        ctx.invoiceAmount = calcAmountOrMin ctx
        
        setupTest ctx
        .then (ctx) ->
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:ctx.invoiceAmount}
            setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}

            return epi.run 'paymentSchema/test/setupTestInvoices', setup
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            return epi.run 'paymentSchema/test/getDurationAdjustments', {}
        .then (results) ->
            assert.ok results
            assert.equal results.length,1
            assert.equal results[0].AMOUNT, 100, "adjustment amount"
            assert.equal results[0].CURRENCY_CODE, 'USD', "adjustment currency code"
            assert.equal results[0].INVOICE_TYPE, 'Adjustment', "adjustment invoice type"
            resolve()
        .catch (err) ->
            reject err  


test 'adjustUsingMostRecentAdjustment', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:200
            markedDownRate:200 #(45+15)/60*200=200
            durationOverrideMinutes:90 #90/60*200=300
        ctx.invoiceAmount = calcAmountOrMin ctx
        
        setupTest ctx
        .then (ctx) ->
            #add a second override for more time
            data = 
                meetingMinutes:ctx.meetingMinutes
                prepMinutes:ctx.prepMinutes
                minProjectAmount:ctx.minProjectAmount
                markedDownRate:ctx.markedDownRate
                durationOverrideMinutes:105 #105/60*200=350 this is 150 extra
                glgPersonId:ctx.glgPersonId

            return epi.run 'paymentSchema/test/setupCpOverride', data
        .then (results) ->
            if !results or results.length <= 0
                throw new Error 'setupCpOverride failed'
            ctx.cpId = results[0].CONSULTATION_PARTICIPANT_ID
            ctx.personId = results[0].PERSON_ID
            return ctx
        .then (ctx) ->
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:ctx.invoiceAmount}
            setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}

            return epi.run 'paymentSchema/test/setupTestInvoices', setup
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            return epi.run 'paymentSchema/test/getDurationAdjustments', {}
        .then (results) ->
            assert.ok results
            assert.equal results.length,1
            assert.equal results[0].AMOUNT, 150, "adjustment amount"
            assert.equal results[0].CURRENCY_CODE, 'USD', "adjustment currency code"
            assert.equal results[0].INVOICE_TYPE, 'Adjustment', "adjustment invoice type"
            resolve()
        .catch (err) ->
            reject err  

test 'accountsForPreviousAdjustments', (assert) ->
    return new Promise (resolve, reject) ->
        ctx =
            assert:assert 
            meetingMinutes:45
            prepMinutes:15
            minProjectAmount:null
            markedDownRate:200
            durationOverrideMinutes:90 #90/60*200=300, thats 30min extra, $100 extra
        ctx.invoiceAmount = calcAmountOrMin ctx
        
        setupTest ctx
        .then (ctx) ->
            setup = entries:[],invoices:[],invoiceConsultations:[],assignments:[],votes:[]
            index = 0
            setup.entries.push {personId:ctx.personId,currencyCode:'USD',amount:ctx.invoiceAmount}
            setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            setup.invoiceConsultations.push {invoiceIndex:index,cpId:ctx.cpId}

            return epi.run 'paymentSchema/test/setupTestInvoices', setup
        .then () ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then (results) ->
            #create a second override
            ctx.durationOverrideMinutes = 105 #105/60*200=400, that's 15mins more, $50 extra
            data = 
                meetingMinutes:ctx.meetingMinutes
                prepMinutes:ctx.prepMinutes
                minProjectAmount:ctx.minProjectAmount
                markedDownRate:ctx.markedDownRate
                durationOverrideMinutes:ctx.durationOverrideMinutes
                glgPersonId:ctx.glgPersonId
                cpId:ctx.cpId

            return epi.run 'paymentSchema/test/setupCpOverride', data
        .then (ctx) ->
            return epi.run 'paymentSchema/createAdjustments', {}
        .then () ->
            return epi.run 'paymentSchema/test/getDurationAdjustments', {}
        .then (results) ->
            assert.ok results
            assert.equal results.length,2
            assert.equal results[0].AMOUNT, 100, "adjustment amount"
            assert.equal results[0].CURRENCY_CODE, 'USD', "adjustment currency code"
            assert.equal results[0].INVOICE_TYPE, 'Adjustment', "adjustment invoice type"
            assert.equal results[1].AMOUNT, 50, "adjustment amount"
            assert.equal results[1].CURRENCY_CODE, 'USD', "adjustment currency code"
            assert.equal results[1].INVOICE_TYPE, 'Adjustment', "adjustment invoice type"            
            resolve()
        .catch (err) ->
            reject err              