def harborCredentialBinding() {
    return usernamePassword(
        credentialsId: 'harbor',
        usernameVariable: 'HARBOR_USER',
        passwordVariable: 'HARBOR_PASSWORD'
    )
}

pipeline {
    agent any

    options {
        timestamps()
        skipDefaultCheckout()
        disableConcurrentBuilds()
        timeout(time: 120, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        choice(
            name: 'APP_BRANCH',
            choices: ['staging', 'master'],
            description: 'staging deploys staging; master deploys production'
        )
    }

    environment {
        APP_BASE_DIR = 'core-api'
        APP_REPO_URL = 'git@github.com:innovity-technologiesinc/sena-project.git'
        APP_GIT_CREDENTIALS = 'github-access'
        IMAGE_URL = 'imageregistry.gen-itech.com'
        IMAGE_REPO = 'senacoreapi/coreapi'
        DOCKER_BUILDKIT = '1'
        ANSIBLE_FORCE_COLOR = 'false'
    }

    stages {
        stage('Checkout CI/CD Repository') {
            steps {
                cleanWs()
                checkout scm
            }
        }

        stage('Select Environment') {
            steps {
                script {
                    def environments = [staging: 'staging', master: 'production']
                    if (!environments.containsKey(params.APP_BRANCH)) {
                        error('Unsupported application branch; select staging or master')
                    }
                    env.DEPLOY_ENV = environments[params.APP_BRANCH]
                }
            }
        }

        stage('Checkout Application Repository') {
            steps {
                dir(env.APP_BASE_DIR) {
                    git(
                        url: env.APP_REPO_URL,
                        branch: params.APP_BRANCH,
                        credentialsId: env.APP_GIT_CREDENTIALS
                    )
                    script {
                        def revision = sh(
                            script: 'git rev-parse --short=12 HEAD',
                            returnStdout: true
                        ).trim()
                        env.IMAGE_TAG = "${env.DEPLOY_ENV}-${env.BUILD_NUMBER}-${revision}"
                        currentBuild.description = "${env.DEPLOY_ENV}: ${env.IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Build Application Image') {
            steps {
                dir(env.APP_BASE_DIR) {
                    sh '''docker build --target prod --file Dockerfile \
                        --tag "$IMAGE_URL/$IMAGE_REPO:$IMAGE_TAG" .'''
                }
            }
        }

        stage('Push Application Image') {
            steps {
                withCredentials([harborCredentialBinding()]) {
                    sh '''#!/bin/sh
                        set -eu
                        set +x
                        umask 077
                        sena_docker_config=$(mktemp -d)
                        trap 'rm -rf "$sena_docker_config"' EXIT
                        trap 'exit 130' INT
                        trap 'exit 143' TERM
                        export DOCKER_CONFIG="$sena_docker_config"
                        printf '%s' "$HARBOR_PASSWORD" | docker login "$IMAGE_URL" \
                            --username "$HARBOR_USER" --password-stdin
                        docker push "$IMAGE_URL/$IMAGE_REPO:$IMAGE_TAG"
                    '''
                }
            }
        }

        stage('Ansible Deployment') {
            options {
                timeout(time: 60, unit: 'MINUTES')
            }
            steps {
                withCredentials([
                    harborCredentialBinding(),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-app-key", variable: 'SENA_APP_KEY'),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-db-password", variable: 'SENA_DB_PASSWORD'),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-cgw-api-token", variable: 'SENA_CGW_API_TOKEN'),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-mail-password", variable: 'SENA_MAIL_PASSWORD'),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-google-maps-api-key", variable: 'SENA_GOOGLE_MAPS_API_KEY')
                ]) {
                    sh 'sh scripts/deploy-from-jenkins.sh'
                }
            }
        }
    }

    post {
        success {
            echo "Completed ${env.DEPLOY_ENV}: ${env.IMAGE_TAG}"
        }
        unsuccessful {
            echo 'Deployment did not complete. Inspect retained Swarm migration tasks before retrying.'
        }
        cleanup {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}
