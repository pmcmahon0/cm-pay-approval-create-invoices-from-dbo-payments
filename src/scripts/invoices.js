

var invoiceModule = (function (epiqueryModule) {

    var path = "paymentSchema/approval/";
    var power = Math.pow(10, 2);

    return {

        currencyFormat: function(amount) {
            return amount.toLocaleString("en-US",{ style: 'currency', currency: 'USD' });
        },

        currencyRound: function(amount) {
            return Math.round(amount * power) / power;
        },

        getApprovalGroupMembership: function (loggedInPersonId) {
            return epiqueryModule.run('glglive', path + "getApprovalGroupMembership.mustache", {loggedInPersonId:loggedInPersonId});
        },

        getNextInvoiceToApprove: function (loggedInPersonId,currentInvoiceId) {
            return epiqueryModule.run('glglive', path + "getNextInvoiceToApprove.mustache", {loggedInPersonId:loggedInPersonId,currentInvoiceId:currentInvoiceId})
            .then ((dbResults) => {
                if (_.isEmpty(dbResults)) {
                    console.log("No more invoices to approve");
                    return;
                }
                var result = dbResults[0];
                console.log("Next invoice is " + result.INVOICE_ID + " for a " + result.KIND);
                return this.getInvoiceDetail(result.INVOICE_ID,result.KIND);
                
            });
            // don't catch, we want caller to handle errors
        },

        getInvoiceDetail: function (invoiceId, kind) {
            var detailPromise = null;
            var data = { invoiceId:invoiceId};
            if (kind === 'Consultation') {
                detailPromise =  epiqueryModule.run('glglive', path + "getConsultationApprovalDetail.mustache", data);
            }
            else if (kind === 'Survey') {
                detailPromise =  epiqueryModule.run('glglive', path + "getSurveyApprovalDetail.mustache", data);
            }
            else if (kind === 'Expense') {
                detailPromise =  epiqueryModule.run('glglive', path + "getExpenseApprovalDetail.mustache", data);
            }
            else if (kind === 'EventVisit') {
                detailPromise =  epiqueryModule.run('glglive', path + "getEventVisitApprovalDetail.mustache", data);
            }
            else if (kind === 'Adjustment') {
                detailPromise =  epiqueryModule.run('glglive', path + "getAdjustmentApprovalDetail.mustache", data);
            } 
            else if (kind === 'CallInterpreter') {
                detailPromise =  epiqueryModule.run('glglive', path + "getConsultationApprovalDetail.mustache", data);
            }                        
            else {
                throw new Error("Unknown 'kind' value: " + kind);
            }
            // note we nest this next step rather than chain it to distinguish 
            // the case of having no more invoices to approve from not being
            // able to retrieve the detail for the next invoice
            return detailPromise
            .then ((dbResults) => {
                if (_.isEmpty(dbResults) || dbResults[0].length === 0) {
                    throw new Error("Failed to get payment request detail");
                }
                var invoices           = dbResults[0];
                var clients            = dbResults[1];
                var notes              = dbResults[2];
                var invoice            = invoices[0];

                if (kind === 'Expense'){
                    //TO DO: this is the only thing we can check for allowed expense
                    //should come from the DB after checking for other meals on the same day
                    //invoice.WARNING = "This invoice is over the allowed budget of XXX";
                }

                invoice.EXPENSE_DATE  = invoice.EXPENSE_DATE ? new moment(invoice.EXPENSE_DATE).local().format('MM/DD/YYYY') : '';
                invoice.USD_AMOUNT = invoiceModule.currencyFormat(invoice.USD_AMOUNT);

                var name = invoice.PAYMENT_ACCOUNT_NAME;
                if (name && name.length > 0) {
                    parenAccountId = invoice.PAYMENT_ACCOUNT_NAME += "(" + invoice.PAYMENT_ACCOUNT_ID.toString() + ")";
                    if (name.indexOf(parenAccountId) < 0) { // scrubbed db has names that include the account id
                        name += " " + parenAccountId;   
                    }
                }
                else {
                    invoice.PAYMENT_ACCOUNT_NAME = invoice.PAYMENT_ACCOUNT_ID ? invoice.PAYMENT_ACCOUNT_ID.toString() : null;
                }
                
                // expense or project invoices related to an event,visit,or conference call
                // may have multiple clients  
                invoice["CLIENTS"] = [];
                for (client of clients) {
                    invoice.CLIENTS.push({ CLIENT_ID: client.CLIENT_ID, CLIENT_NAME: client. CLIENT_NAME });
                }
                invoice["NOTES"] = [];
                if (notes) {
                    for (note of notes) {
                        note.CREATE_DATE = this.formatDateLocalHours(note.CREATE_DATE);
                        invoice.NOTES.push(note);
                    }
                }
                return invoice;
            });
        },

        getApprovedInvoices: function () {
            return epiqueryModule.run('glglive', path + "getApprovedInvoices.mustache", {});
        },

        approve: function (loggedInPersonId, invoiceId) {
            var approval = {
                approvedInd: '1',
                invoiceId: invoiceId,
                loggedInPersonId: loggedInPersonId, 
            };
            return epiqueryModule.run('glglive', path + "upsertApproval.mustache", approval);
        },

        reject: function (loggedInPersonId, invoiceId, note) {
            // don't touch the holdInd; the UI relies on it to detect changes in the hold list
            var approval = {
                approvedInd: '0',
                invoiceId: invoiceId,
                loggedInPersonId: loggedInPersonId,
                note: note,
            };
            return epiqueryModule.run('glglive', path + "upsertApproval.mustache", approval);                       
        },

        hold: function(loggedInPersonId, invoiceId, note) {
            var data = {
                holdInd: '1',
                invoiceId: invoiceId,
                loggedInPersonId: loggedInPersonId,
                note: note,
            };         
            return epiqueryModule.run('glglive', path + "upsertApproval.mustache", data);
        },

        getHolds: function (loggedInPersonId) {
            return epiqueryModule.run('glglive', path + "getApprovalHolds.mustache", {loggedInPersonId:loggedInPersonId});
        },

        getMostRecentHoldDate: function() {
            return epiqueryModule.run('glglive', path + "getMostRecentHoldDate.mustache", {});
        },

        getPendingTotal: function(loggedInPersonId) {
            return epiqueryModule.run('glglive', path + "getPendingTotal.mustache", {loggedInPersonId:loggedInPersonId});
        },

        getAccountingContext: function(payeePersonId,loggedInPersonId) {
            return epiqueryModule.run('glglive', path + "getAccountingContext.mustache", {payeePersonId:payeePersonId,loggedInPersonId:loggedInPersonId});
        },

        getEventsContext: function(payeePersonId,loggedInPersonId,invoiceId) {
            return epiqueryModule.run('glglive', path + "getEventsContext.mustache", {payeePersonId:payeePersonId,loggedInPersonId:loggedInPersonId,invoiceId:invoiceId});
        },

        getCmProjects: function(cmId) {
            return epiqueryModule.run('glglive', "cm-pay/getCmProjects.mustache", {cmId:cmId});
        },

        getClients: function(clients) {
            var arr = [];
            for (client of clients) {
                arr.push({ CLIENT_ID: client.CLIENT_ID, CLIENT_NAME: client.CLIENT_NAME });
            }
            return arr;
        },

        getProjectDetail: function(data) {
            return epiqueryModule.run('glglive', path + "getProjectDetail.mustache", data)
            .then ((dbResults) => {
                if (_.isEmpty(dbResults) || dbResults[0].length === 0) {
                    throw new Error("Failed to get payment request detail");
                }
                var detail = dbResults[0][0]
                detail.CLIENTS=this.getClients(dbResults[1]);              

                return detail;           
            });
        },

        cloneInvoiceWithChanges: function(data)   {
            return epiqueryModule.run('glglive', path + "cloneInvoiceWithChanges.mustache",data);
        },

        assignInvoicesForApproval: function() {
            return epiqueryModule.run('glglive', path + "assignInvoicesForApproval.mustache",{});
        },

        getCmSfdcId: function(cmVegaId) {
            return epiqueryModule.run('sfdc', "paymentSchema/getCmSfdcId.mustache",{cmVegaId:cmVegaId});
        },

        addNote: function (loggedInPersonId, invoiceId, note) {
            var data = {
                invoiceId: invoiceId,
                loggedInPersonId: loggedInPersonId,
                note: note,
            };
            return epiqueryModule.run('glglive', path + "addNote.mustache", data)
            .then ((dbResults) => {
                if (dbResults && dbResults.length > 0) {
                    var note = dbResults[0];
                    note.CREATE_DATE = this.formatDateLocalHours(note.CREATE_DATE);
                }
                return note;
            });                     
        },

        formatDateLocalHours: function(dt) {
            return  dt ? new moment(dt).local().format('MM/DD/YYYY H.m A') : '';
        },
    }

})(epiqueryModule);
