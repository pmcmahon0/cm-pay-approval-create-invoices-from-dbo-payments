# test-assign-invoices.coffee

test           = require 'blue-tape'
Epiquery       = require '../devUtil/lib/epi-request'
Promise        = require 'bluebird' 
invoiceCreator = require '../devUtil/lib/invoice-creator'
moment         = require 'moment' 
_              = require 'lodash' 
util           = require './util'

epi            = new Epiquery {verbose: false}
glgPersonId    = null
eventIds       = []
cps            = { phoneConsultations:[],nonPhoneConsultations:[] }
qualtricsIds   = []
survey2Ids     = []

nonPhoneConsultationCategoryName = 'Written Report' # NULL is second most common next to Phone Consultation but my local db has none with NULL

#exit if environment not setup
if typeof process.env.EPIQUERY_SERVER == 'undefined'
    console.log "Environment variables have not been sourced."
    process.exit() 

ensureGlgPersonId = () ->
    return Promise.resolve glgPersonId if glgPersonId
    return epi.run 'employee/getEmployee', {loginName:'pmcmahon'}
    .then (results) ->
        glgPersonId = results[0].personId
        return glgPersonId

ensureEventIds = () ->
    return epi.run 'paymentSchema/test/getProjectIds', {howMany:2,projectType:'event'}
    .then (dbResults) ->
        _.each dbResults, (dbResult) -> eventIds.push(dbResult.EVENT_ID)

ensureQualtricsIds = () ->
    return epi.run 'paymentSchema/test/getProjectIds', {howMany:2,projectType:'qualtrics'}
    .then (dbResults) ->
        _.each dbResults, (dbResult) -> qualtricsIds.push(dbResult.SURVEY_ID)

ensureSurvey2Ids = () ->
    return epi.run 'paymentSchema/test/getProjectIds', {howMany:2,projectType:'survey2'}
    .then (dbResults) ->
        _.each dbResults, (dbResult) -> survey2Ids.push(dbResult.SURVEY_ID)                

setUpConsultationParticipants = () ->
    return epi.run 'paymentSchema/test/setUpConsultationParticipantsForComplianceMemberStatusTesting', {}
    .then (dbResults) ->
        cps.phoneConsultations    = []
        cps.nonPhoneConsultations = []
        _.each dbResults[0],   (cp) -> cps.phoneConsultations.push(cp)
        _.each dbResults[1],   (cp) -> cps.nonPhoneConsultations.push(cp)
        # console.log "cps.phoneConsultations", JSON.stringify cps.phoneConsultations
        # console.log "cps.nonPhoneConsultations", JSON.stringify cps.nonPhoneConsultations

getCpIdByCriteria = (criteria) ->
    return cps.nonPhoneConsultations[0].cpId if !criteria
    cons = if criteria.isPhoneConsultation then cps.phoneConsultations else cps.nonPhoneConsultations
    con = _.find cons, (v,k) -> return v.markedDownRate == criteria.markedDownRate
    return con.cpId
                
reset = (ctx) ->
    return epi.run 'paymentSchema/devUtils/clearAllData', {}
    .then (results) => return util.ensureApprovalGroups()
    .then (results) => return util.ensureCmInfos()
    .then (results) => return ensureEventIds()
    .then (results) => return setUpConsultationParticipants()
    .then (results) => return ensureQualtricsIds()
    .then (results) => return ensureSurvey2Ids()
    .then (results) => return ensureGlgPersonId()
    .then (id) =>
        ctx.glgPersonId = id
        return ctx

setupCpOverride = (ctx) ->
    data = 
        meetingMinutes                             : ctx.adjustmentData.meetingMinutes
        prepMinutes                                : ctx.adjustmentData.prepMinutes
        minProjectAmount                           : ctx.adjustmentData.minProjectAmount
        markedDownRate                             : ctx.adjustmentData.markedDownRate
        durationOverrideMinutes                    : ctx.adjustmentData.meetingMinutes + ctx.adjustmentData.prepMinutes + ctx.adjustmentData.extraMinutes
        glgPersonId                                : ctx.adjustmentData.glgPersonId
        productCategoryName                        : ctx.adjustmentData.consultationProductCategoryName

    return epi.run 'paymentSchema/test/setupCpOverride', data
    .then (results) =>
        if !results or results.length <= 0
            throw new Error 'setupCpOverride failed'

        ctx.cpIdForAdjustment = results[0].CONSULTATION_PARTICIPANT_ID
        ctx.cmPersonIdForAdjustment = results[0].PERSON_ID
        return ctx;

verifyAssignments = (assert,assignments,expectedAssignments) ->
    assignmentsByGroup = _.groupBy assignments, 'APPROVAL_GROUP_NAME'
    _.forEach expectedAssignments, (v,k) ->
        console.log k, v
        assert.ok !_.isUndefined(assignmentsByGroup[k]), "group #{k} should be in assignments"
        if !_.isUndefined assignmentsByGroup[k]
            assert.equal v, assignmentsByGroup[k].length, "expected #{v} assigned to #{k}; found #{assignmentsByGroup[k].length}"

    extras = _.difference (_.keys assignmentsByGroup), (_.keys expectedAssignments)
    assert.equal extras.length, 0, "unexpected assignments: #{_.join extras, ','}"

invoiceAssignQueryAndVerify = (ctx,expectedAssignments) ->
    return epi.run 'paymentSchema/test/setupTestInvoices', ctx.setup
    .then (dbResults) =>
        return epi.run 'paymentSchema/test/backDateInvoicesForAssignment', {}
    .then (dbResults) =>
        return epi.run 'paymentSchema/approval/assignInvoicesForApproval', {}
    .then (dbResults) =>
        return epi.run 'paymentSchema/createAdjustments', {}
    .then (dbResults) =>
        return epi.run 'paymentSchema/test/backDateInvoicesForAssignment', {}
    .then (dbResults) =>        
        return epi.run 'paymentSchema/approval/assignInvoicesForApproval', {}
    .then (dbResults) =>      
        return epi.run 'paymentSchema/test/getApprovals', {}
    .then (dbResults) =>
        verifyAssignments ctx.assert, dbResults[0], expectedAssignments

commonTest = (assert,which,amounts,expectedAssignments,adjustmentData,cpCriteria) ->
    if !consultationCategoryName then consultationCategoryName = nonPhoneConsultationCategoryName

    return new Promise (resolve, reject) =>    
        ctx = {assert:assert}
        reset(ctx)
        .then () =>
            if which == 'consultationWithPrepTimeAndAdjustment'
                ctx.adjustmentData = adjustmentData
                ctx.adjustmentData.glgPersonId = glgPersonId
                return setupCpOverride ctx
            return ctx
        .then (ctx) =>
            ctx.cmInfos = _.take util.getCmsWithSinglePaymentAccount(), 1
            ctx.setup = {entries:[],invoices:[],invoiceConsultations:[],invoiceEvents:[],invoiceSurvey2s:[],invoiceQualtrics:[],expenses:[]}

            cpId = getCpIdByCriteria cpCriteria
            personId = ctx.cmInfos[0].PERSON_ID

            if which == 'consultationWithPrepTimeAndAdjustment'
                cpId = ctx.cpIdForAdjustment
                personId = ctx.cmPersonIdForAdjustment

            index = 0
            if which == 'expense' 
                eventIdIndex = 0
                _.forEach amounts, (meetingAmounts) ->
                    _.forEach meetingAmounts, (meetingAmount) ->
                        ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:meetingAmount}
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Other'}
                        ctx.setup.invoiceEvents.push {eventId:eventIds[eventIdIndex],invoiceIndex:index}
                        ctx.setup.expenses.push {invoiceIndex:index} 
                        index++
                    eventIdIndex++

            else 
                if which != 'consultationWithPrepTimeAndAdjustment' 
                    ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:amounts[0]}

                switch which
                    when 'event'
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Honorarium'}
                        ctx.setup.invoiceEvents.push {invoiceIndex:index, eventId:eventIds[0]}
                        console.log "set up #{which} invoices"
                    when 'qualtrics'
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Honorarium'}
                        ctx.setup.invoiceQualtrics.push {invoiceIndex:index, qualtricsId:qualtricsIds[0]}
                        console.log "set up #{which} invoices"
                    when 'survey2'
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Honorarium'}
                        ctx.setup.invoiceSurvey2s.push {invoiceIndex:index, survey2Id:survey2Ids[0]}
                        console.log "set up #{which} invoices"
                    when 'consultation'
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
                        ctx.setup.invoiceConsultations.push {invoiceIndex:index, cpId:cpId}
                        console.log "set up #{which} invoices"                 
                    when 'consultationWithPrepTime'
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
                        ctx.setup.invoiceConsultations.push {invoiceIndex:index, cpId:cpId}
                        index++
                        ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:amounts[1]}
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Prep Time'}
                        ctx.setup.invoiceConsultations.push {invoiceIndex:index, cpId:cpId} 
                        console.log "set up #{which} invoices" 
                    when 'consultationWithPrepTimeAndAdjustment'
                        ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:adjustmentData.markedDownRate*adjustmentData.meetingMinutes/60}
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
                        ctx.setup.invoiceConsultations.push {invoiceIndex:index, cpId:cpId}
                        index++
                        ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:adjustmentData.markedDownRate*adjustmentData.prepMinutes/60}
                        ctx.setup.invoices.push {entryIndex:index,invoiceType:'Prep Time'}
                        ctx.setup.invoiceConsultations.push {invoiceIndex:index, cpId:cpId}                        

            return invoiceAssignQueryAndVerify ctx, expectedAssignments
        .then () => resolve()
        .catch (err) -> reject err

#=================================TESTS=================================

# you can write 'test.only' to run a single specific test -- as for debugging

# parameters: assert,which,amounts,expectedAssignments,adjustmentData,cpCriteria

test 'event2000',           (assert) -> return commonTest assert, 'event',       [2000], { "Accounting":1 }
test 'qualtrics2000',       (assert) -> return commonTest assert, 'qualtrics',   [2000], { "Accounting":1 }
test 'survey2000',          (assert) -> return commonTest assert, 'survey2',     [2000], { "Accounting":1 }
test 'consultation2000',    (assert) -> return commonTest assert, 'consultation',[2000], { "Accounting":1 }, null, { isPhoneConsultation:0, markedDownRate:2000 }

test 'event2500',           (assert) -> return commonTest assert, 'event',       [2500], { "Accounting":1,"Compliance Member Status":1 }
test 'qualtrics2500',       (assert) -> return commonTest assert, 'qualtrics',   [2500], { "Accounting":1,"Compliance Member Status":1 }
test 'survey2500',          (assert) -> return commonTest assert, 'survey2',     [2500], { "Accounting":1,"Compliance Member Status":1 }
test 'consultation2500',    (assert) -> return commonTest assert, 'consultation',[2500], { "Accounting":1,"Compliance Member Status":1 }, null, { isPhoneConsultation:0, markedDownRate:2500 }

test 'event10000',          (assert) -> return commonTest assert, 'event',       [10000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1 }
test 'qualtrics10000',      (assert) -> return commonTest assert, 'qualtrics',   [10000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1 }
test 'survey10000',         (assert) -> return commonTest assert, 'survey2',     [10000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1 }
test 'consultation10000',   (assert) -> return commonTest assert, 'consultation',[10000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1 }, null, { isPhoneConsultation:0, markedDownRate:10000 }

test 'event25000',          (assert) -> return commonTest assert, 'event',       [25000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1,"Compliance Senior Legal":1 }
test 'qualtrics25000',      (assert) -> return commonTest assert, 'qualtrics',   [25000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1,"Compliance Senior Legal":1 }
test 'survey25000',         (assert) -> return commonTest assert, 'survey2',     [25000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1,"Compliance Senior Legal":1 }
test 'consultation25000',   (assert) -> return commonTest assert, 'consultation',[25000], { "Accounting":1,"Compliance Member Status":1,"Comptroller":1,"Compliance Senior Legal":1 }, null, { isPhoneConsultation:0, markedDownRate:25000 }

# compliance does not want events; only events team, accounts payable and comptroller do
test 'expenses2000',        (assert) -> return commonTest assert, 'expense', [[2000,500]],           { "Events":2, "Accounts Payable":2 }
test 'expenses2500',        (assert) -> return commonTest assert, 'expense', [[2500,500]],           { "Events":2, "Accounts Payable":2 }
test 'expenses10000',       (assert) -> return commonTest assert, 'expense', [[8000,2000],[10000]],  { "Events":3, "Accounts Payable":3, "Comptroller":1 }                    
test 'expenses25000',       (assert) -> return commonTest assert, 'expense', [[16000,9000],[25000]], { "Events":3, "Accounts Payable":3, "Comptroller":2 } 

test 'doesNotAssignPhoneConsultationsUnder4xThresholdToComplianceMemberStatus', (assert) -> return commonTest assert, 'consultation', [2500], { "Accounting":1 }, null, { isPhoneConsultation:1, markedDownRate:2500 }
test 'assignsNonPhoneConsultationsUnder4xThresholdToComplianceMemberStatus', (assert) -> return commonTest assert, 'consultation', [2500], { "Accounting":1, "Compliance Member Status":1 }, null, { isPhoneConsultation:0, markedDownRate:2500 }
test 'assignsPhoneConsultationsAtOrOver4xThresholdToComplianceMemberStatus', (assert) -> return commonTest assert, 'consultation', [2000], { "Accounting":1, "Compliance Member Status":1 }, null, { isPhoneConsultation:1, markedDownRate:500 }

test 'consultationWithPrepTime2000', (assert) ->
    return commonTest assert, 'consultationWithPrepTime',[1950,50], { "Accounting":2 }  

test 'consultationWithPrepTime2500', (assert) ->
    return commonTest assert, 'consultationWithPrepTime',[2450,50], { "Accounting":2, "Compliance Member Status":2 }  

test 'consultationWithPrepTime10000', (assert) ->
    return commonTest assert, 'consultationWithPrepTime',[9000,1000], { "Accounting":2, "Compliance Member Status":2, "Comptroller":2 }      

test 'consultationWithPrepTime25000', (assert) ->
    return commonTest assert, 'consultationWithPrepTime',[24000,1000], {"Accounting":2, "Compliance Member Status":2, "Comptroller":2, "Compliance Senior Legal":2 }                       

test 'consultationWithPrepTimeAndAdjustment2000', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 1000            
        meetingMinutes   : 60*1.5    # $1500
        prepMinutes      : 60*0.25   # $ 250
        extraMinutes     : 60*0.25   # $ 250 
        consultationProductCategoryName : nonPhoneConsultationCategoryName

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3 }, adjustmentData

test 'consultationWithPrepTimeAndAdjustment2500', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 1000            
        meetingMinutes   : 60*2      # $2000 
        prepMinutes      : 60*0.25   # $ 250
        extraMinutes     : 60*0.25   # $ 250 
        consultationProductCategoryName : nonPhoneConsultationCategoryName        

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3, "Compliance Member Status":3 }, adjustmentData

test 'consultationWithPrepTimeAndAdjustment10000', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 2000            
        meetingMinutes   : 60*4       # $8000
        prepMinutes      : 60*0.5     # $1000
        extraMinutes     : 60*0.5     # $1000
        consultationProductCategoryName : nonPhoneConsultationCategoryName

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3, "Compliance Member Status":3, "Comptroller":3 }, adjustmentData

test 'consultationWithPrepTimeAndAdjustment25000', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 2000            
        meetingMinutes   : 60*8   # $16000
        prepMinutes      : 60*4   # $ 8000
        extraMinutes     : 60*1   # $ 2000
        consultationProductCategoryName : nonPhoneConsultationCategoryName

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3, "Compliance Member Status":3, "Comptroller":3, "Compliance Senior Legal":3 }, adjustmentData
              

test 'excludesComplianceMemberStatusFromPhoneConsultationLessThanOrEqualTo4HoursPay', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 1000            
        meetingMinutes   : 60*2      # $2000
        prepMinutes      : 60*0.25   # $ 250
        extraMinutes     : 60*0.5    # $ 500         
        consultationProductCategoryName : 'Phone Consultation'

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3 }, adjustmentData

test 'includesComplianceMemberStatusFromPhoneConsultationOver4HoursPay', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 1000            
        meetingMinutes   : 60*4      # $4000
        prepMinutes      : 60*0.25   # $ 250
        extraMinutes     : 60*0.5    # $ 500         
        consultationProductCategoryName : 'Phone Consultation'

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3, "Compliance Member Status":3 }, adjustmentData, {isPhoneConsultation:1,markedDownRate:1000}

test 'doesNotExcludeComplianceMemberStatusFromNonPhoneConsultationLessThanOrEqualTo4HoursPay', (assert) ->
    adjustmentData = 
        minProjectAmount : null
        markedDownRate   : 1000            
        meetingMinutes   : 60*2      # $2000
        prepMinutes      : 60*0.25   # $ 250
        extraMinutes     : 60*0.5    # $2750       
        consultationProductCategoryName : nonPhoneConsultationCategoryName

    return commonTest assert, 'consultationWithPrepTimeAndAdjustment',null, {"Accounting":3, "Compliance Member Status":3 }, adjustmentData, {isPhoneConsultation:0,markedDownRate:1000}

test 'interpreterConsultationsUnder2500', (assert) ->
    return new Promise (resolve, reject) =>
        ctx = {assert:assert}
        reset(ctx)
        .then () =>
            intCpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:2000}
            cm1CpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:500}
            cm2CpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:1000}
            return epi.run 'paymentSchema/test/insertCallInterpreters', {callInterpreters:[ { interpreterCpId : intCpId, originalCpId : cm1CpId }, { interpreterCpId : intCpId, originalCpId : cm2CpId } ]}
        .then (rows) =>
            callInterpreterIds =  _.flatMap rows, (row) -> row.CALL_INTERPRETER_ID

            ctx = {assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)}
            ctx.setup = {entries:[],invoices:[],invoiceInterpreters:[]}
            personId = ctx.cmInfos[0].PERSON_ID

            # note that currently prep time is n/a to interpreters            

            index = 0
            ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:2000}
            ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            ctx.setup.invoiceInterpreters.push {invoiceIndex:index,callInterpreterId:callInterpreterIds[0]} # right now there is no check that they belong the same consulation, so good enuf for testing

            index++
            ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:1000}
            ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            ctx.setup.invoiceInterpreters.push {invoiceIndex:index,callInterpreterId:callInterpreterIds[1]}

            return invoiceAssignQueryAndVerify ctx, {"Accounting":2}
        .then () => resolve()
        .catch (err) -> reject err  

test 'interpreterConsultationOver2500AndUnder25000', (assert) ->
    return new Promise (resolve, reject) =>
        ctx = {assert:assert}
        reset(ctx)
        .then () =>
            intCpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:2000}
            cm1CpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:500}
            cm2CpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:1000}
            return epi.run 'paymentSchema/test/insertCallInterpreters', {callInterpreters:[ { interpreterCpId : intCpId, originalCpId : cm1CpId }, { interpreterCpId : intCpId, originalCpId : cm2CpId } ]}
        .then (rows) =>
            callInterpreterIds =  _.flatMap rows, (row) -> row.CALL_INTERPRETER_ID

            ctx = {assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)}
            ctx.setup = {entries:[],invoices:[],invoiceInterpreters:[]}
            personId = ctx.cmInfos[0].PERSON_ID

            # note that currently prep time is n/a to interpreters

            index = 0
            ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:2500}
            ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            ctx.setup.invoiceInterpreters.push {invoiceIndex:index,callInterpreterId:callInterpreterIds[0]} # right now there is no check that they belong the same consulation, so good enuf for testing

            index++
            ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:1500}
            ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            ctx.setup.invoiceInterpreters.push {invoiceIndex:index,callInterpreterId:callInterpreterIds[1]}

            return invoiceAssignQueryAndVerify ctx, {"Accounting":2,"Compliance Member Status":1}
        .then () => resolve()
        .catch (err) -> reject err  

test 'interpreterConsultationOver25000', (assert) ->
    return new Promise (resolve, reject) =>
        ctx = {assert:assert}
        reset(ctx)
        .then () =>
            intCpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:2000}
            cm1CpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:500}
            cm2CpId = getCpIdByCriteria { isPhoneConsultation:0,markedDownRate:1000}
            return epi.run 'paymentSchema/test/insertCallInterpreters', {callInterpreters:[ { interpreterCpId : intCpId, originalCpId : cm1CpId }, { interpreterCpId : intCpId, originalCpId : cm2CpId } ]}
        .then (rows) =>
            callInterpreterIds =  _.flatMap rows, (row) -> row.CALL_INTERPRETER_ID

            ctx = {assert:assert,cmInfos:_.take(util.getCmsWithSinglePaymentAccount(),1)}
            ctx.setup = {entries:[],invoices:[],invoiceInterpreters:[]}
            personId = ctx.cmInfos[0].PERSON_ID

            # note that currently prep time is n/a to interpreters

            index = 0
            ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:25000}
            ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            ctx.setup.invoiceInterpreters.push {invoiceIndex:index,callInterpreterId:callInterpreterIds[0]} # right now there is no check that they belong the same consulation, so good enuf for testing
       
            index++
            ctx.setup.entries.push {personId:personId,currencyCode:'USD',amount:9000}
            ctx.setup.invoices.push {entryIndex:index,invoiceType:'Meeting Time'}
            ctx.setup.invoiceInterpreters.push {invoiceIndex:index,callInterpreterId:callInterpreterIds[1]}

            return invoiceAssignQueryAndVerify ctx, {"Accounting":2,"Compliance Senior Legal":1,"Compliance Member Status":2,"Comptroller":1}
        .then () => resolve()
        .catch (err) -> reject err

