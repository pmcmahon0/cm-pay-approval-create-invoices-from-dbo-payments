#!/bin/bash

coffee -c -o js util.coffee
coffee -c -o js/lib lib/*.coffee
source dev.env

node js/util.js --how-many 1 --consultation  --adjustment
# node js/util.js --how-many 1 --event
# node js/util.js --how-many 1 --visit
# node js/util.js --how-many 1 --survey
# node js/util.js --how-many 1 --qualtrics-survey
# node js/util.js --how-many 2 --event-expense
# node js/util.js --how-many 1 --callInterpreter

# use the --legacy flag to create dbo.payments records
# that https://github.com/glg/cm-pay-approval-jobs/blob/master/create-invoices-for-new-payments
# can convert to invoices

# need to pull this out from history as well:
# https://github.com/glg/epiquery-templates/blob/80dd029d4c7b173285452b656ccc597e8502f035/paymentSchema/prodTest/createInvoicesForNewPayments.mustache

# not used
# node js/util.js --how-many 1 --consultation --legacy
# node js/util.js --how-many 1 --event --legacy
# node js/util.js --how-many 1 --visit --legacy
# node js/util.js --how-many 1 --survey --legacy
# node js/util.js --how-many 1 --qualtrics-survey --legacy
# node js/util.js --how-many 1 --event-expense --legacy

# node js/util.js --assign
