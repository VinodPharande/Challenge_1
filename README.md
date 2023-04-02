# This will be implemented using Terraform as IaaC tool, GCP as a cloud provider.    

## Understanding notes: 

1. Will targetting landing zone concept, so Dev env associated with terraform dev workspace and tf dev workspace mapped to GCP dev project. 

2. So while provisioing GCP resource, if we made any file change in specific env folder, TF will detect the change in that folder and accordingly start the resource deployment.  

3. These are resources will provisioned or used im this 3-Tier application:  
	a. Secret Manager: To store secret key required for deployments.  
	b. Cloud Build: To build, pacage and deploy front end and back end application.  
	c. Cloud Run: To run front and and back end application in container as a serverless way.  
	d. Cloud SQL: Managed SQL for database layer of an application.  
	b. Cloud Memorystore: To provide caching layer for an application.  