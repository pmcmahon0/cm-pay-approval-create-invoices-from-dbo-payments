config                 = require('./lib/config')
program                = require('commander')
_                      = require('lodash')
bluebird               = require('bluebird')
moment                 = require('moment')
invoiceCreator         = require('./lib/invoice-creator')

#exit if environment not setup
if typeof process.env.GLGENV == 'undefined'
    console.log "Environment variables have not been sourced."
    process.exit()

listArg = (val) ->
    return val.split ','

parseCommandLine = () ->
    program
    .option '-a, --assign ', 'Assign for approval'
    .option '-r, --approve <n> ', 'Approve by approval group'
    .option '-c, --consultation ', 'Consultation'
    .option '-j, --adjustment ', 'Adjustment (only valid with consultation and not legacy)'
    .option '-e, --event ', 'Event'
    .option '-x, --event-expense ', 'Event Expense'
    .option '-l, --legacy ', 'Legacy'
    .option '-q, --qualtrics-survey ', 'Qualtrics Survey'
    .option '-s, --survey ', 'Survey'
    .option '-v, --visit ', 'Visit'
    .option '-i, --callInterpreter', 'Call Interpreter'
    .option '-u, --use-consultation-id ', 'Create legacy payment for consultation, setting consultation_id'
    .option '-h, --how-many <n>', 'How many invoices to create', parseInt
    .option '-p, --person-id <n>', 'Person ID', parseInt
    .parse process.argv

parseCommandLine()

howMany = 1
loggedInPersonId = 249861  #Mike O'Hair
legacy = false
useConsultationId = false

howMany = program.howMany if program.howMany
loggedInPersonId = program.personId if program.personId
legacy = program.legacy if program.legacy
useConsultationId = program.useConsultationId if program.useConsultationId
durationAdjustment = program.adjustment if program.consultation and program.adjustment
callInterpreter = program.adjustment if program.callInterpreter

projectTypes = []

projectTypes.push 'consultation' if program.consultation
projectTypes.push 'event' if program.event
projectTypes.push 'visit' if program.visit
projectTypes.push 'survey' if program.survey
projectTypes.push 'qualtricsSurvey' if program.qualtricsSurvey
projectTypes.push 'callInterpreter' if program.callInterpreter

expenseTypes = []

expenseTypes.push 'eventExpense' if program.eventExpense

ctx = { invoiceIds: [], createInfos: [] }

# we use mapSeries because want all the epiquery requests to execute sequentially
# to avoid epiquery running out of connections or sql deadlocking

bluebird.mapSeries projectTypes, (projectType) ->
    return invoiceCreator.getProjectInvoiceCreateInfo howMany, projectType
    .then (createInfos) ->
        ctx.createInfos.push createInfos
        bluebird.mapSeries createInfos, (createInfo) ->
            createInfo["loggedInPersonId"]   = loggedInPersonId
            createInfo["useConsultationId"]  = useConsultationId
            createInfo["legacy"]             = legacy
            createInfo["durationAdjustment"] = durationAdjustment
            createInfo["callInterpreter"]    = callInterpreter
            createInfo.invoiceIds            = []  

            invoiceCreator.createProjectInvoice createInfo
            .then (invoiceIds) -> 
                ctx.invoiceIds.push.apply ctx.invoiceIds, invoiceIds

.then (result) ->
    return bluebird.mapSeries expenseTypes, (expenseType) ->
        invoiceCreator.getExpenseInvoiceCreateInfo howMany, expenseType
        .then (createInfos) ->
            bluebird.mapSeries createInfos, (createInfo) ->
                createInfo["legacy"]           = legacy
                createInfo["loggedInPersonId"] = loggedInPersonId
                createInfo.invoiceIds          = []
                invoiceCreator.createExpenseInvoice createInfo
                .then (invoiceIds) -> 
                    ctx.invoiceIds.push.apply ctx.invoiceIds, invoiceIds

.then (result) ->
    console.log "ctx.invoiceIds", JSON.stringify ctx.invoiceIds
    return invoiceCreator.backDateInvoices ctx.invoiceIds
.then (result) ->
    return invoiceCreator.assignInvoicesForApproval() if program.assign
.then (result) ->
    console.log "Done"
.catch (err) ->
    console.log "#{err.message}\n#{err.stack}"
