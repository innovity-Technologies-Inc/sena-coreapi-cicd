pipeline {
    agent any

    options {
        timestamps()
        skipDefaultCheckout()
        disableConcurrentBuilds()
    }

    environment {
        APP_BASE_DIR = 'core-api'
        DOCKER_BUILDKIT = '1'
        APP_REPO_URL = 'git@github.com:innovity-technologiesinc/sena-project.git'
        IMAGE_URL= "imageregistry.gen-itech.com"
        IMAGE_REPO = "senacoreapi/coreapi"
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        DOCKERFILE_PATH = "core-api"
        DOCKERFILE_SUFFIX = "Dockerfile"
    }

    // Chose Branch Name 
    parameters {
        choice(
            name: 'APP_BRANCH',
            choices: ['dev', 'staging', 'master'],
            description: 'Select the git branch for application to build'
        )
    }

    stages {

        stage('Show Branch Selection') {
            steps {
                echo "Selected Branch: ${params.APP_BRANCH}"
            }
        }

        // Checkout CI/CD Repo

        stage('Checkout CI/CD Repo') {
            steps {
                cleanWs()
                checkout scm 
            }
        }



        // Checkout Application Repo

        stage('Checkout Application Repo') {
            steps {
                dir(env.APP_BASE_DIR) {
                    git url: APP_REPO_URL, branch: params.APP_BRANCH
                }
            }
        }


        // set Environment 

        stage('Set Deployment Environment') {
            steps {
                script {
                    if (params.APP_BRANCH == 'master') {
                        env.DEPLOY_ENV = 'production'
                    } else if (params.APP_BRANCH == 'staging') {
                        env.DEPLOY_ENV = 'staging'
                    } else {
                        params.APP_BRANCH = 'dev'
                    }
                }
            }
        }



        stage('Docker Image Build') {

            steps {
                        dir("${env.APP_BASE_DIR}") {
                            sh """ 
                            docker build -t ${IMAGE_URL}/${IMAGE_REPO}:${IMAGE_TAG} .
                            docker tag ${IMAGE_URL}/${IMAGE_REPO}:${IMAGE_TAG} ${IMAGE_URL}/${IMAGE_REPO}:latest
                            """
                            //  trivy image --exit-code 1 ${DOCKER_REGISTRY}/composition:${IMAGE_TAG}                           
                        }
                }
        }

        stage('Harbor Login') {
            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'harbor',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASSWORD'
                    )
                ]) {

                    sh """
                    echo \$HARBOR_PASSWORD | docker login ${env.IMAGE_URL} \
                    -u \$HARBOR_USER \
                    --password-stdin
                    """
                }
            }
        }


     // Docker push Images
        stage('Push Docker Image') {
            steps {
                    sh """
                    docker push ${IMAGE_URL}/${IMAGE_REPO}:${IMAGE_TAG}
                    docker push ${IMAGE_URL}/${IMAGE_REPO}:latest
                    """
                }
            }

    }

        // Deploy Using Ansible & Docker Compose 

        stage('Deploy using Ansible') {
            steps {
                sh """
                ansible-playbook \
                  -i ansible/inventory/${DEPLOY_ENV}.ini \
                  ansible/deploy-app.yml \
                  -e image_tag=latest
                """
            }
        }
    }


