Python Code Library App — CI/CD Pipeline Documentation

📖 Overview
A complete end-to-end CI/CD pipeline for a multi-service Python Flask application, deployed to a 3-node Docker Swarm cluster on AWS. The pipeline automates code checkout, quality analysis, container build, vulnerability scanning, image publishing, and deployment.
Repo: https://github.com/Harshithajam/python-code-library-app

🏗️ Architecture

 ┌──────────┐    git push    ┌──────────────┐
│  GitHub  │───────────────▶│   Webhook    │
└──────────┘                └──────┬───────┘
                                   │
                                   ▼
                        ┌──────────────────────┐
                        │   Jenkins Master     │
                        │   (EC2, port 8080)   │
                        └──────────┬───────────┘
                                   │  dispatches build
                                   ▼
                        ┌──────────────────────┐       ┌────────────┐
                        │  Jenkins Agent       │──CQA─▶│ SonarQube  │
                        │  on Swarm Manager    │       │ (EC2:9000) │
                        └──────────┬───────────┘       └────────────┘
                                   │
                                   │  docker build / push / stack deploy
                                   ▼
                        ┌──────────────────────┐       ┌────────────┐
                        │   Docker Hub         │◀──────│  Trivy     │
                        │   (image registry)   │       │  (scan)    │
                        └──────────┬───────────┘       └────────────┘
                                   │  docker pull
                                   ▼
                        ┌──────────────────────────────────────────┐
                        │          Docker Swarm Cluster            │
                        │   ┌──────────┐  ┌──────────┐ ┌────────┐  │
                        │   │ Manager  │  │ Worker1  │ │Worker2 │  │
                        │   │(control) │  │ (tasks)  │ │(tasks) │  │
                        │   └──────────┘  └──────────┘ └────────┘  │
                        └──────────────────────────────────────────┘



🧰 Technology Stack

Layer	Tool	Purpose
Source Control	GitHub	Code repository
CI Orchestrator	Jenkins 2.580+	Pipeline execution
Build Agent	Jenkins SSH Agent on Swarm Manager	Runs pipeline stages
Static Analysis	SonarQube 9.x	Code quality + quality gate
Vulnerability Scan	Trivy	Container image scanning
Container Registry	Docker Hub	Image storage
Container Runtime	Docker 25.x	Container engine
Orchestration	Docker Swarm	1 manager + 2 workers
Base OS	Amazon Linux 2023	EC2 instances
Language Runtime	Python 3.9-slim	Application base image

📦 Application Services
Service	File	Port	Purpose
frontend	app.py	5000	Web UI
auth_service	auth/auth_service.py	5001	Authentication microservice
book_service	book/book_service.py	5002	Book management
borrow_service	borrow/borrow_service.py	5003	Borrow management
db	mysql:5.7	3306	Database




Inter-service communication uses Swarm's internal DNS with service names:
•	http://auth_service:5001
•	http://book_service:5002
•	http://borrow_service:5003


🔄 Pipeline Stages

#	Stage	Purpose	Runs On
1	code	Clone repo, wipe workspace for clean state	Jenkins Agent
2	cqa	SonarQube static analysis	Jenkins Agent
3	Quality Gate	Blocks pipeline if SonarQube gate fails	Jenkins Agent
4	images	Build Docker image tagged with ${BUILD_NUMBER} and latest	Swarm Manager
5	scan	Trivy vulnerability scan (report-only)	Swarm Manager
6	push	Push both tags to Docker Hub	Swarm Manager
7	deploy on stack	Deploy to Swarm with new tag	Swarm Manager




📜 Jenkinsfile

pipeline {
    agent { label 'manager' }

    options {
        buildDiscarder(logRotator(numToKeepStr: '3'))
    }

    triggers {
        githubPush()
    }

    stages {
        stage('code') {
            steps {
                deleteDir()
                git branch: 'master',
                    url: 'https://github.com/Harshithajam/python-code-library-app.git'
            }
        }

        stage('cqa') {
            steps {
                withSonarQubeEnv('mysonar') {
                    sh 'sonar-scanner -Dsonar.projectKey=python-code-library-app -Dsonar.sources=.'
                }
            }
        }

        stage('Quality Gate') {
            steps {
                waitForQualityGate abortPipeline: true, credentialsId: 'mysonar'
            }
        }

        stage('images') {
            steps {
                script {
                    def image = "harshithajam/python-code-library-app"
                    sh """
                        sg docker -c 'docker build -t ${image}:${BUILD_NUMBER} -t ${image}:latest .'
                    """
                }
            }
        }

        stage('scan') {
            steps {
                script {
                    def image = "harshithajam/python-code-library-app"
                    sh """
                        sg docker -c 'trivy image ${image}:${BUILD_NUMBER} --severity HIGH,CRITICAL --format table' || true
                    """
                }
            }
        }

        stage('push') {
            steps {
                script {
                    def image = "harshithajam/python-code-library-app"
                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            sg docker -c 'echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin'
                            sg docker -c 'docker push ${image}:${BUILD_NUMBER}'
                            sg docker -c 'docker push ${image}:latest'
                            sg docker -c 'docker logout'
                        """
                    }
                }
            }
        }

        stage('deploy on stack') {
            steps {
                script {
                    def image = "harshithajam/python-code-library-app"
                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            sg docker -c 'echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin'
                            sg docker -c 'export TAG=${BUILD_NUMBER} && docker stack deploy -c compose.yml --with-registry-auth python-lib-stack'
                            sg docker -c 'docker stack services python-lib-stack'
                        """
                    }
                }
            }
        }
    }
}	

Pipeline Behavior Notes
•	buildDiscarder — Jenkins keeps only the last 3 builds, dropping older ones automatically
•	githubPush() — Triggers on git push via webhook (requires Jenkins job config checkbox too)
•	deleteDir() — Wipes the workspace before checkout, preventing stale files
•	sg docker -c '...' — Wraps Docker commands because the Jenkins SSH agent doesn't inherit supplementary groups

📄 Dockerfile
Located at the repo root:
 
Key points:
•	COPY . . includes all service directories (auth/, book/, borrow/, templates/, database/)
•	Single image serves all services — compose.yml overrides command: per service

📄 compose.yml
version: "3.8"

services:
  db:
    image: mysql:5.7
    environment:
      MYSQL_ROOT_PASSWORD: devopspassword
      MYSQL_DATABASE: library
    ports:
      - "3306:3306"
    volumes:
      - mydata:/var/lib/mysql
      - ./database:/docker-entrypoint-initdb.d
    networks:
      - myapp
    deploy:
      replicas: 1
      resources:
        reservations: { cpus: "0.25", memory: 100M }
        limits:        { cpus: "0.5",  memory: 200M }

  auth_service:
    image: harshithajam/python-code-library-app:${TAG:-latest}
    command: python auth/auth_service.py
    ports: ["5001:5001"]
    depends_on: [db]
    networks: [myapp]
    deploy:
      replicas: 1
      resources:
        reservations: { cpus: "0.25", memory: 100M }
        limits:        { cpus: "0.5",  memory: 200M }

  book_service:
    image: harshithajam/python-code-library-app:${TAG:-latest}
    command: python book/book_service.py
    ports: ["5002:5002"]
    depends_on: [db]
    networks: [myapp]
    deploy:
      replicas: 1
      resources:
        reservations: { cpus: "0.25", memory: 100M }
        limits:        { cpus: "0.5",  memory: 200M }

  borrow_service:
    image: harshithajam/python-code-library-app:${TAG:-latest}
    command: python borrow/borrow_service.py
    ports: ["5003:5003"]
    depends_on: [db]
    networks: [myapp]
    deploy:
      replicas: 1
      resources:
        reservations: { cpus: "0.25", memory: 100M }
        limits:        { cpus: "0.5",  memory: 200M }

  frontend:
    image: harshithajam/python-code-library-app:${TAG:-latest}
    ports: ["5000:5000"]
    depends_on: [auth_service, book_service, borrow_service]
    networks: [myapp]
    deploy:
      replicas: 1
      resources:
        reservations: { cpus: "0.25", memory: 100M }
        limits:        { cpus: "0.5",  memory: 200M }

networks:
  myapp:
    driver: overlay

volumes:
  mydata:

Key points:
•	${TAG:-latest} — falls back to latest if TAG env var isn't set
•	The pipeline sets TAG=${BUILD_NUMBER} so the deploy uses the freshly built image
•	driver: overlay — required for Swarm (not bridge)
•	--with-registry-auth on deploy passes Docker Hub credentials to workers


🚀 Setup Guide
Prerequisites
•	AWS account with EC2 access
•	Docker Hub account with repo python-code-library-app
•	Forked GitHub repository
•	SonarQube instance (or skip the cqa/Quality Gate stages)

EC2 Instances
Instance	Role	Suggested Type
jenkins-master	Jenkins controller	c7i-flex.large
swarm-manager	Swarm manager + Jenkins agent	c7i-flex.large
swarm-worker-1	Swarm worker	t3.small
swarm-worker-2	Swarm worker	t3.small
sonarqube	Static analysis 	c7i-flex.large

Note : we can install sonarqube in Jenkins-master server itself

Security Group
All Swarm nodes must share a security group (or allow each other) with these inbound rules:
Type	Port	Protocol	Source	Purpose
SSH	22	TCP	Your IP	Admin
Custom TCP	2377	TCP	SG itself	Swarm control plane
Custom TCP	7946	TCP	SG itself	Node gossip
Custom UDP	7946	UDP	SG itself	Node gossip
Custom UDP	4789	UDP	SG itself	VXLAN overlay
Custom TCP	5000-5003	TCP	0.0.0.0/0	App ports
Custom TCP	8080	TCP	Your IP	Jenkins UI
Custom TCP	9000	TCP	Your IP	SonarQube UI

Swarm Initialization
On the manager:
Command:
docker swarm init --advertise-addr <manager-private-ip>
docker swarm join-token worker

Run the printed join command on each worker.
Verify:
Command:
docker node ls

Jenkins Agent Setup
On the manager, install Java 21:
Command:
sudo yum install -y java-21-amazon-corretto-devel
In Jenkins: Manage Jenkins → Nodes → New Node
•	Name: swarm-manager
•	Label: manager
•	Remote root: /home/ec2-user/jenkins-agent
•	Launch method: SSH (as ec2-user with your .pem key)

Jenkins Credentials
ID	Kind	Value
dockerhub-creds	Username + password	Docker Hub username + PAT
sonar-token	Secret text	SonarQube user token



GitHub Webhook
Repo → Settings → Webhooks → Add:
•	Payload URL: http://<jenkins-public-ip>:8080/github-webhook/
•	Content type: application/json
•	Events: Just the push event
Then in the Jenkins job config, check GitHub hook trigger for GITScm polling.

🧪 Verification
Cluster health -manager
Commands:
docker node ls
docker stack services python-lib-stack
docker stack ps python-lib-stack

Application access
Commands:
curl -I http://localhost:5000
curl -I http://<manager-public-ip>:5000
curl -I http://<worker1-public-ip>:5000

All three should return HTTP 200 (or a redirect).

Service logs
Commands:
docker service logs python-lib-stack_frontend --tail 50
docker service logs python-lib-stack_auth_service --tail 50
docker service logs python-lib-stack_db --tail 50



Database check
Commands:
docker exec -it $(docker ps -q -f name=db) \
  mysql -uroot -pdevopspassword -e "SHOW DATABASES;"


🔧 Troubleshooting
Symptom	Cause	Fix
permission denied on docker.sock	Jenkins user not in docker group	usermod -aG docker ec2-user, restart agent
can't open file '/app/auth/...'	Image missing directories	Ensure Dockerfile has COPY . . and no restrictive .dockerignore
network cannot be used with services	Bridge network cached	docker network rm python-lib-stack_myapp then redeploy
Site unreachable after deploy	Port not in security group	Add inbound rule for the port
Site reachable on one node only	Port 7946 blocked	Add TCP + UDP 7946 to security group
this node is not a swarm manager	Swarm not initialized	docker swarm init --advertise-addr <ip>
Quality gate always fails	Coverage on new code = 0%	Copy "Sonar way" gate, remove coverage condition
sonar-scanner: command not found	Binary not on PATH for agent	Use full path or Docker variant
Could not find credentials matching	Wrong credential ID	Verify ID matches dockerhub-creds exactly
unauthorized on push	Using account password	Regenerate as Personal Access Token



📊 Image Retention
Location	Retention Policy
Jenkins builds	Last 3 (buildDiscarder(numToKeepStr: '3'))
Local Docker on manager	Manual cleanup (extend post block if needed)
Docker Hub	Configure via repo settings → Retention

🔐 Security Notes

•	Never commit secrets — SonarQube tokens, DB passwords, and Docker Hub tokens belong in Jenkins Credentials
•	Use Personal Access Tokens for Docker Hub, not account passwords
•	Rotate tokens periodically, especially if exposed
•	Keep manager drained in production: docker node update --availability drain manager
•	SonarQube on embedded H2 is evaluation-only — migrate to PostgreSQL for real use
•	Use .dockerignore to exclude .git, .env, and virtual environments from the image

📚 Key Lessons

1.	Docker socket permissions on Jenkins agents — SSH sessions don't inherit supplementary groups; either enable UsePAM in sshd or wrap commands with sg docker -c
2.	Swarm requires overlay networks — bridge is host-scoped and rejected by docker stack deploy
3.	Port 7946 (TCP + UDP) is mandatory for Swarm — without it, gossip fails and cross-node routing mesh breaks
4.	Docker caches images by tag — even with --with-registry-auth, a stale tag can be reused; unique tags per build solve this
5.	COPY . . needs .dockerignore — otherwise .git, .scannerwork, and build artifacts bloat the image
6.	docker stack deploy ignores container_name — Swarm generates its own names
7.	AWS security groups are the #1 cause of "works locally, not externally" — always verify inbound rules first
8.	Docker Hub requires Personal Access Tokens for CLI authentication — account passwords are deprecated for this use

📞 Project Info
Author: Harshitha Jam
Repository: https://github.com/Harshithajam/python-code-library-app
Image: harshithajam/python-code-library-app
Stack Name: python-lib-stack

