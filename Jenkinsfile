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
        // BASE_URL= "https://codeserver.gen-itech.com/admin"
        IMAGE_URL= "imageregistry.gen-itech.com"
        IMAGE_REPO = "senacoreapi/coreapi"
        // DOCKER_REGISTRY = "zhddoc"
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        DOCKERFILE_PATH = "docker"
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

        // Unit Testing 
        // stage('Unit Testing') {
        //     steps {
        //         dir(env.APP_BASE_DIR) {
        //             sh './mvnw clean test'
        //         }
        //     }
        // }

        // Integration Testing
        // stage('Integration Testing') {
        //     steps {
        //         sh './mvnw clean integration-test'
        //     }
        // }

        // Dependency Security Scan using OWASP

        // Docker Image BUILD & Scan 
        // stage('Docker Build & Scan') {
        //     parallel {
        //         stage('Migrate Image') {
        //             steps {
        //                 dir("${env.APP_BASE_DIR}") {
        //                     sh """ 
        //                     docker build -t ${DOCKER_REGISTRY}/migrate:${IMAGE_TAG} -f ${DOCKERFILE_PATH}/migrate.${DOCKERFILE_SUFFIX} .
        //                     docker tag ${DOCKER_REGISTRY}/migrate:${IMAGE_TAG} ${DOCKER_REGISTRY}/migrate:latest
        //                     """
        //                     //  trivy image --exit-code 1 ${DOCKER_REGISTRY}/composition:${IMAGE_TAG}                           
        //                 }
        //             }
        //         }

        //     }
        // }

        // Docker Login
        // stage('Docker Login') {
        //     steps {
        //         withCredentials([usernamePassword(credentialsId: 'docker', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
        //             sh "echo $PASS | docker login -u $USER --password-stdin"
        //         }
        //     }
        // }

        stage('Docker Image Build') {
            steps {
                script {

                    docker_build(
                        env.IMAGE_URL,
                        env.IMAGE_REPO,
                        env.IMAGE_TAG
                    )

                    sh """
                    docker tag \
                    ${env.IMAGE_URL}/${env.IMAGE_REPO}:${env.IMAGE_TAG} \
                    ${env.IMAGE_URL}/${env.IMAGE_REPO}:latest
                    """
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


        // // Docker push Images
        // stage('Docker Push Images') {
        //     steps {
        //         script {
        //             def services = ["migrate", "composition", "renewal", "notification"]

        //             services.each { service ->
        //                 sh "docker push $DOCKER_REGISTRY/${service}:$IMAGE_TAG"
        //                 sh "docker push $DOCKER_REGISTRY/${service}:latest"
        //             }
        //         }
        //     }
        // }

     // Docker push Images
        stage('Push Docker Image') {
            steps {
                script {

                    docker_push(
                        env.IMAGE_URL,
                        env.IMAGE_REPO,
                        env.IMAGE_TAG
                    )

                    sh """
                    docker push ${env.IMAGE_URL}/${env.IMAGE_REPO}:latest
                    """
                }
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
    post {
        success {
            echo "Deployment Successful to ${DEPLOY_ENV}"
        }
        failure {
            echo "Deployment failed"
        }
        always {
            junit '**/target/surefire-reports/*.xml'
        }
    }
}

