# cm-pay-approval util


In the `util` directory

```
	npm install
	sh run.sh
```

This will clear any existing payments ready for approval and create some `dbo.payment` records that are ready for approval. 

Note, we make use the obsolete `prepaid_ind` flag on the `dbo.payment` record to exclude (true) or include (fase) a payment for approval.