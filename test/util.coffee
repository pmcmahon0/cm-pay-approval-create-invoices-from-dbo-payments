#util.coffee

Epiquery                              = require '../devUtil/lib/epi-request'
_                                     = require 'lodash' 
epi                                   = new Epiquery {verbose: false}
approvalGroupMembersByGroupName       = null
approvalGroupByName                   = null
cmInfosByPersonId                     = null
cmsWithDistinctExpensePaymentAccounts = null
cmsWithSinglePaymentAccount           = null
glgPersonId                           = null

module.exports =

    ensureApprovalGroups:() ->
        return Promise.resolve {} if approvalGroupByName and approvalGroupMembersByGroupName
        return epi.run 'paymentSchema/test/getApprovalGroups', {}
        .then (results) ->
            #first result set is APPROVAL_GROUP_ID/APPROVAL_GROUP_NAME
            approvalGroupByName = _.keyBy results[0], (item) ->
                return item.APPROVAL_GROUP_NAME

            #second is APPROVAL_GROUP_ID/PERSON_ID
            approvalGroupMembersByGroupName = {}
            _.map results[1], (item) ->
                approvalGroupMembersByGroupName[item.APPROVAL_GROUP_NAME] = [] if !approvalGroupMembersByGroupName[item.APPROVAL_GROUP_NAME]
                approvalGroupMembersByGroupName[item.APPROVAL_GROUP_NAME].push item.PERSON_ID
            return Promise.resolve {}

    getApprovalGroupByName: () ->
        throw new Error "Missing call to ensureApprovalGroups()" if !approvalGroupByName
        return approvalGroupByName
    getApprovalGroupMembersByGroupName: () ->
        throw new Error "Missing call to ensureApprovalGroups()" if !approvalGroupMembersByGroupName
        return approvalGroupMembersByGroupName        

    getEventsPersonId: (index) ->
        throw new Error "Missing call to ensureApprovalGroups()" if !approvalGroupByName
        return approvalGroupMembersByGroupName['Events'][index]

    getAccountingPersonId: (index) ->
        throw new Error "Missing call to ensureApprovalGroups()" if !approvalGroupByName
        return approvalGroupMembersByGroupName['Accounting'][index] 

    ensureCmInfos: () =>
        return Promise.resolve {} if cmInfosByPersonId
        return epi.run 'paymentSchema/test/getCmInfo', {howMany:100}
        .then (results) ->

            cmInfosByPersonId = _.keyBy results, (result) -> result.PERSON_ID
            halves = _.partition cmInfosByPersonId, (cmInfo) ->
                expAcct = if cmInfo.EXPENSE_PAYMENT_ACCOUNT_ID then cmInfo.EXPENSE_PAYMENT_ACCOUNT_ID else cmInfo.PROJECT_PAYMENT_ACCOUNT_ID
                return cmInfo.PROJECT_PAYMENT_ACCOUNT_ID == expAcct

            cmsWithSinglePaymentAccount           = halves[0]
            cmsWithDistinctExpensePaymentAccounts = halves[1]

            # console.log "cmsWithSinglePaymentAccount", JSON.stringify cmsWithSinglePaymentAccount
            # console.log "cmsWithDistinctExpensePaymentAccounts", JSON.stringify cmsWithDistinctExpensePaymentAccounts
            
            return Promise.resolve {} 

    getCmInfosByPersonId: () ->
        throw new Error "Missing call to ensureCmInfos()" if !cmInfosByPersonId
        return cmInfosByPersonId 

    getCmsWithSinglePaymentAccount: () ->
        throw new Error "Missing call to ensureCmInfos()" if !cmInfosByPersonId or !cmsWithSinglePaymentAccount
        return cmsWithSinglePaymentAccount

    getCmsWithDistinctExpensePaymentAccounts: () ->
        throw new Error "Missing call to ensureCmInfos()" if !cmInfosByPersonId or !cmsWithDistinctExpensePaymentAccounts
        return cmsWithDistinctExpensePaymentAccounts 

    ensureGlgPersonId: () ->
        return Promise.resolve glgPersonId if glgPersonId
        return epi.run 'employee/getEmployee', {loginName:'pmcmahon'}
        .then (results) ->
            glgPersonId = results[0].personId
            return glgPersonId                         
