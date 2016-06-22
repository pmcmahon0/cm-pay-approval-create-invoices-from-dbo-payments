config   = require('./config')

program  = require('commander')
_        = require('lodash')
bluebird = require('bluebird')
moment   = require('moment')
Epiquery = require './epi-request'

epi      = new Epiquery {verbose: false}

createSomeExpenses = (meetingId, meetingDate, cmPersonId, cmId, paymentAccountId) ->
    invoices = []

    invoice =
        amount: 100.21
        countryCode: "US"
        currencyCode: "USD"
        description: "Travel to the meeting"
        distance: 200
        eventId: meetingId
        expenseDate: meetingDate
        invoiceTypeName: 'Transportation'
        legacyCountryId: 1
        legacyMileageUnit: "Miles"
        loggedInPersonId: cmPersonId
        payeePersonId: cmPersonId
        receiptsUrl: null
        unit:"MILE" #one of: "MILE", "KMET"
        cmId:cmId

    invoices.push invoice

    invoice =
        amount: 80.60
        countryCode: "US"
        currencyCode: "USD"
        description: "Travel from the meeting"
        distance: 200
        eventId: meetingId
        expenseDate: meetingDate
        invoiceTypeName: 'Transportation'
        legacyCountryId: 1
        legacyMileageUnit: "Miles"
        loggedInPersonId: cmPersonId
        payeePersonId: cmPersonId
        receiptsUrl: null
        unit:"MILE" #one of: "MILE", "KMET"
        cmId:cmId

    invoices.push invoice        

    invoice =
        amount: 500.23
        currencyCode: "CAD"
        description: "A place to lay my head"
        expenseDate: meetingDate
        invoiceTypeName: 'Lodging'
        loggedInPersonId: cmPersonId
        eventId: meetingId
        payeePersonId: cmPersonId
        receiptsUrl: null
        cmId:cmId

    invoices.push invoice

    invoice =
        amount: 10.53
        currencyCode: "CAD"
        description: "breakfast"
        expenseDate: meetingDate
        invoiceTypeName: 'Meals'
        loggedInPersonId: cmPersonId
        eventId: meetingId
        payeePersonId: cmPersonId
        receiptsUrl: null
        cmId:cmId

    invoices.push invoice

    invoice =
        amount: 20.96
        currencyCode: "CAD"
        description: "dinner"
        expenseDate: meetingDate
        invoiceTypeName: 'Meals'
        loggedInPersonId: cmPersonId
        eventId: meetingId
        payeePersonId: cmPersonId
        receiptsUrl: null
        cmId:cmId

    invoices.push invoice    

    return invoices


createConsultationInvoice = (createInfo) ->
    if createInfo.legacy
        paymentRequestInfo =
            useConsultationId: createInfo.useConsultationId
            loggedInPersonId: createInfo.loggedInPersonId
            meetingId: createInfo.PROJECT_ID
            prepMinutes: 15
            meetingMinutes: 45
            councilMemberId: createInfo.COUNCIL_MEMBER_ID

        return epi.run 'paymentSchema/devUtils/createLegacyConsultationPayment', paymentRequestInfo

    invoices = []

    invoice = 
        currencyCode: "USD"
        loggedInPersonId: createInfo.loggedInPersonId
        payeePersonId: createInfo.PERSON_ID
        cpId: createInfo.CONSULTATION_PARTICIPANT_ID
        invoiceType: 'Meeting Time'
        minutes: 45
        cmId:createInfo.COUNCIL_MEMBER_ID

    invoices.push invoice

    invoice = 
        currencyCode: "USD"
        loggedInPersonId: createInfo.loggedInPersonId
        payeePersonId: createInfo.PERSON_ID
        cpId: createInfo.CONSULTATION_PARTICIPANT_ID
        invoiceType: 'Prep Time'
        minutes: 15
        cmId:createInfo.COUNCIL_MEMBER_ID

    invoices.push invoice

    return bluebird.mapSeries invoices, (invoice) ->
        epi.run 'cm-pay/upsertInvoice', invoice

createEventVisitInvoice = (createInfo) ->
    if createInfo.legacy
        paymentRequestInfo =
            amount: 2000
            loggedInPersonId: createInfo.loggedInPersonId
            eventTableId: createInfo.PROJECT_ID
            councilMemberId: createInfo.COUNCIL_MEMBER_ID

        return epi.run 'paymentSchema/devUtils/createLegacyEventVisitPayment',paymentRequestInfo

    invoice = 
        currencyCode: "USD"
        loggedInPersonId: createInfo.loggedInPersonId
        payeePersonId: createInfo.PERSON_ID
        consultation_participant_id: createInfo.PROJECT_ID
        amount: 550
        eventId: createInfo.PROJECT_ID
        invoiceType: 'Honorarium'
        cmId:createInfo.COUNCIL_MEMBER_ID

    return epi.run 'cm-pay/upsertInvoice', invoice

createSurveyInvoice = (createInfo) ->
    if createInfo.legacy
        paymentRequestInfo =
            amount: 160
            councilMemberId: createInfo.COUNCIL_MEMBER_ID
            loggedInPersonId: createInfo.loggedInPersonId
            surveyId: createInfo.PROJECT_ID

        return epi.run 'paymentSchema/devUtils/createLegacySurveyPayment',paymentRequestInfo

    invoice = 
        currencyCode: "USD"
        loggedInPersonId: createInfo.loggedInPersonId
        payeePersonId: createInfo.PERSON_ID
        consultation_participant_id: createInfo.PROJECT_ID
        invoiceType: 'Honorarium'
        amount: 150
        cmId:createInfo.COUNCIL_MEMBER_ID

    if createInfo.PROJECT_TYPE == 'survey'
        invoice.smpSurveyId = createInfo.PROJECT_ID
    else if createInfo.PROJECT_TYPE == 'qualtricsSurvey'
        invoice.qualtricsSurveyId = createInfo.PROJECT_ID

    return epi.run 'cm-pay/upsertInvoice', invoice


createMeetingExpenseInvoice = (createInfo) ->
    expenses = createSomeExpenses createInfo.PROJECT_ID, new moment().subtract(7, 'd'), createInfo.PERSON_ID, createInfo.COUNCIL_MEMBER_ID, createInfo.PAYMENT_ACCOUNT_ID

    if createInfo.legacy

        paymentRequestInfo =
            items: []
            loggedInPersonId: createInfo.loggedInPersonId
            councilMemberId: createInfo.COUNCIL_MEMBER_ID
            meetingId: createInfo.PROJECT_ID

        for expense in expenses
            item =
                currencyCode: expense.currencyCode
                amount: expense.amount
                expenseDate: expense.expenseDate.local()
                description: expense.description
                receiptsUrl: expense.receiptsUrl
                itemTypeName: expense.invoiceTypeName
                mileageDistance: expense.distance
                mileageUnit: expense.legacyMileageUnit
                mileageCountryId: expense.legacyCountryId

            paymentRequestInfo.items.push item

        return epi.run 'paymentSchema/devUtils/createLegacyExpensePayment',paymentRequestInfo

    invoices = []
    for expense in expenses
        invoice =
            amount: expense.amount
            currencyCode: expense.currencyCode
            description: expense.description
            expenseDate: new moment().subtract(7, 'd').format(),
            invoiceType: expense.invoiceTypeName,
            loggedInPersonId: createInfo.loggedInPersonId,
            payeePersonId: createInfo.PERSON_ID,
            eventId: createInfo.PROJECT_ID
            cmId:createInfo.COUNCIL_MEMBER_ID

        invoices.push invoice

    return bluebird.mapSeries invoices, (invoice) ->
        epi.run 'cm-pay/upsertInvoice', invoice

createInterpretationInvoice = (createInfo) ->
    invoice = 
        currencyCode: "USD"
        loggedInPersonId: createInfo.loggedInPersonId
        payeePersonId: createInfo.PERSON_ID
        callInterpreterId: createInfo.CALL_INTERPRETER_ID
        invoiceType: 'Meeting Time'
        amount: createInfo.MARKED_DOWN_RATE
        minutes: 60
        cmId:createInfo.COUNCIL_MEMBER_ID

    return epi.run 'cm-pay/upsertInvoice', invoice    

logCreatedMessage = (createInfo, result) ->
    #console.log "logCreatedMessage result #{JSON.stringify result}"
    if createInfo.legacy
        paymentId = result.PAYMENT_ID
        paymentId = result[0].PAYMENT_ID if result[0]
        console.log "Created payment #{result[0].PAYMENT_ID} for #{createInfo.PROJECT_TYPE}"
    else
        console.log "Created invoice #{result[0].INVOICE_ID} for #{createInfo.PROJECT_TYPE}"


module.exports =

    getExpenseInvoiceCreateInfo: (howMany, expenseType, cmPersonId) ->
        return epi.run 'paymentSchema/devUtils/getProjectInvoiceCreateInfo',{howMany:howMany,projectType:'event',cmPersonId:cmPersonId}

    getProjectInvoiceCreateInfo: (howMany, projectType, cmPersonId) ->
        return epi.run 'paymentSchema/devUtils/getProjectInvoiceCreateInfo',{howMany:howMany,projectType:projectType,cmPersonId:cmPersonId}

    createProjectInvoice: (createInfo) ->
        legacy = ''
        legacy = 'legacy' if createInfo.legacy
        invoiceIds = []

        console.log "createProjectInvoice for #{createInfo.PROJECT_TYPE}"
        if createInfo.PROJECT_TYPE.toLowerCase() == 'consultation'
            return createConsultationInvoice createInfo
            .then (result) =>
                if createInfo.legacy
                    console.log "Created payment #{result[0].PAYMENT_ID} for consultation"
                else
                    console.log "Created invoices #{result[0][0].INVOICE_ID} and #{result[1][0].INVOICE_ID} (meeting and prep time) for consultation"
                    invoiceIds.push result[0][0].INVOICE_ID
                    invoiceIds.push result[1][0].INVOICE_ID

                if createInfo.durationAdjustment
                    return epi.run 'paymentSchema/devUtils/createDurationOverrideFromInvoice', {invoiceId:result[0][0].INVOICE_ID,extraCmBillableMinutes:30}
                    .then (result) =>
                        console.log "Created consultation duration override #{result[0].OVERRIDE_ID}"
                        return epi.run 'paymentSchema/createAdjustments', {}
                    .then (result) =>
                        if result and result.length > 0
                            console.log "Created duration adjustment invoice #{result[0].INVOICE_ID}" 
                            invoiceIds.push result[0].INVOICE_ID
                        return invoiceIds
                return invoiceIds

        if createInfo.PROJECT_TYPE == 'event' or createInfo.PROJECT_TYPE == 'visit'
            return createEventVisitInvoice createInfo
            .then (result) =>
                logCreatedMessage createInfo, result
                invoiceIds.push result[0].INVOICE_ID
                return invoiceIds

        if createInfo.PROJECT_TYPE == 'survey' or createInfo.PROJECT_TYPE == 'qualtricsSurvey'
            return createSurveyInvoice createInfo
            .then (result) =>
                logCreatedMessage createInfo, result
                invoiceIds.push result[0].INVOICE_ID
                return invoiceIds

        if createInfo.PROJECT_TYPE == 'callInterpreter'
            return createInterpretationInvoice createInfo
            .then (result) =>
                logCreatedMessage createInfo, result
                invoiceIds.push result[0].INVOICE_ID
                return invoiceIds

    createExpenseInvoice : (createInfo) ->
        legacy = ''
        legacy = 'legacy' if createInfo.legacy

        console.log "createExpenseInvoice for #{createInfo.PROJECT_TYPE}"
        return createMeetingExpenseInvoice createInfo
        .then (results) ->
            invoiceIds = []
            for result in results
                if createInfo.legacy
                    console.log "Created payment #{result.PAYMENT_ID} for #{createInfo.PROJECT_TYPE}"
                else
                    logCreatedMessage createInfo, result 
                    invoiceIds.push result[0].INVOICE_ID     
            return invoiceIds

    upsertApproval: (loggedInPersonId, approvalGroupName, paymentId, invoiceId) ->
        approval =
            approvalGroupName: approvalGroupName
            approvedInd: 1
            invoiceId: invoiceId
            loggedInPersonId: loggedInPersonId
            note: 'This is my approval note'
            paymentId: paymentId

        return epi.run 'paymentSchema/approval/upsertApproval', approval

    assignInvoicesForApproval: () ->
        return epi.run 'paymentSchema/approval/assignInvoicesForApproval', {}
        .then (results) ->
            invoiceIds = _.flatMap results, (row) -> return row.INVOICE_ID

    backDateInvoices: (invoiceIds) ->
        if invoiceIds and invoiceIds.length > 0
            return epi.run 'paymentSchema/test/backDateInvoicesForAssignment', {invoiceIds:invoiceIds}
