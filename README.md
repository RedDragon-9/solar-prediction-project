### This is live currently on solar.reddragon09.in

### Automated Solar Irradiance Predictor (AWS Production Pipeline)

DevOps implementation of a stateless **Python/Flask** Machine Learning application that fetches 7-day weather forecasts via WeatherAPI and runs a machine learning regression model to predict solar irradiance. This project uses **Terraform** for Infrastructure as Code (IaC) to dynamically provision and manage cloud architecture in the **AWS Stockholm (eu-north-1) region**, with smart fallbacks to reuse an existing VPC and Application Load Balancer (ALB) if present. 

### Cloud Architecture

* **Hosting Compute Layer:** AWS ECS Express Mode.
* **Network & Security Controls:** Public subnets with outward internet gateways enabling live API requests to api.weatherapi.com. The container runs via a restricted, unprivileged non-root system identity (USER appuser) inside the Docker wrapper layer.
* **Routing Tier:** Adaptive host-header conditional listener rules applied directly to a shared or standalone Application Load Balancer (ALB).
* **Continuous Integration & Deployment:** GitHub Actions orchestrating automated image builds and infrastructure apply pipelines on every push.

### How to Deploy This to Your Own AWS Account

### 1. Prerequisites

* A registered domain configured via an **AWS Route 53 Hosted Zone** (e.g., yourdomain.com).
* An AWS IAM deployment user account(having AdminstratorAccess policy for terraform) with programmatic access keys (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
* An active API key token registered from weatherapi.com. (You get the API key as soon as you sign up at weatherapi.com).
* Unique S3 bucket name.

### 2. Configure GitHub Secrets

Clone or pull this repository to a local repository, navigate to **Settings ➡️ Secrets and variables ➡️ Actions**, and add these **5 Encrypted Secrets** to repository secrets: 

* AWS_ACCESS_KEY_ID - Your programmatic IAM access ID string.
* AWS_SECRET_ACCESS_KEY - Your matching programmatic secret access key.
* MY_ROOT_DOMAIN - Your base hosted zone domain name (e.g., mydomain.com).
* MY_SUBDOMAIN - The subdomain address where the web app will be served (e.g., abc.mydomain.com). (Do not enter only the subdomain (e.g., abc) as the secret value)
* MY_WEATHER_API_KEY - Your secret WeatherAPI key token string.

### 3. Change S3 Bucket Name

* Go to main.tf and change the S3 bucket name for backend located within the first terrafrom{...} block to a different unique name.
* Go to .github/workflows/deploy.yml file and change the bucket name in the Remote state storage section (step 4) to the same name used in main.tf.

### 4. Push and Launch!

Once your secrets are added, push your project modifications to the main branch: 
```
bash

git add .
git commit -m "intial message"
git push origin main
```

The **GitHub Actions pipeline** will automatically fire up, invoke Terraform, discover your existing infrastructure resources or build fallback baselines, compile your hardened container image, inject your weather API key, and route it to your custom domain address with live HTTPS enabled!
