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
            name: 'DEPLOY_MODE',
            choices: ['build-and-deploy', 'redeploy'],
            description: 'Build a new application image or redeploy an existing image with current settings and credentials'
        )
        choice(
            name: 'APP_BRANCH',
            choices: ['staging', 'master'],
            description: 'staging deploys staging; master deploys production'
        )
        string(
            name: 'EXISTING_IMAGE_TAG',
            defaultValue: '',
            description: 'Required for redeploy: an existing environment-build-revision tag, for example staging-42-abc123def456'
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

        stage('Select Deployment') {
            steps {
                script {
                    def environments = [staging: 'staging', master: 'production']
                    if (!environments.containsKey(params.APP_BRANCH)) {
                        error('Unsupported application branch; select staging or master')
                    }
                    env.DEPLOY_ENV = environments[params.APP_BRANCH]
                    def deployMode = params.DEPLOY_MODE ?: 'build-and-deploy'
                    if (!(deployMode in ['build-and-deploy', 'redeploy'])) {
                        error('Unsupported deployment mode; select build-and-deploy or redeploy')
                    }
                    env.DEPLOY_MODE = deployMode
                    if (deployMode == 'redeploy') {
                        def imageTag = (params.EXISTING_IMAGE_TAG ?: '').trim()
                        if (imageTag.length() > 128 || !imageTag.matches(env.DEPLOY_ENV + '-[1-9][0-9]*-[a-f0-9]{7,40}')) {
                            error("EXISTING_IMAGE_TAG must be an immutable ${env.DEPLOY_ENV}-BUILD-REVISION tag")
                        }
                        env.IMAGE_TAG = imageTag
                        currentBuild.description = "redeploy ${env.DEPLOY_ENV}: ${env.IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Checkout Application Repository') {
            when {
                expression { env.DEPLOY_MODE == 'build-and-deploy' }
            }
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
                        currentBuild.description = "build-and-deploy ${env.DEPLOY_ENV}: ${env.IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Build Application Image') {
            when {
                expression { env.DEPLOY_MODE == 'build-and-deploy' }
            }
            steps {
                dir(env.APP_BASE_DIR) {
                    sh '''docker build --target prod --file Dockerfile \
                        --tag "$IMAGE_URL/$IMAGE_REPO:$IMAGE_TAG" .'''
                }
            }
        }

        stage('Push Application Image') {
            when {
                expression { env.DEPLOY_MODE == 'build-and-deploy' }
            }
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
                    string(credentialsId: "cgw-${env.DEPLOY_ENV}-api-key", variable: 'SENA_CGW_API_TOKEN'),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-mail-password", variable: 'SENA_MAIL_PASSWORD'),
                    string(credentialsId: "sena-${env.DEPLOY_ENV}-google-maps-api-key", variable: 'SENA_GOOGLE_MAPS_API_KEY'),
                    file(credentialsId: "cgw-${env.DEPLOY_ENV}-firebase", variable: 'SENA_FIREBASE_KEY_FILE')
                ]) {
                    sh 'sh scripts/deploy-from-jenkins.sh'
                }
            }
        }
    }

    post {
        success {
            echo "Completed ${env.DEPLOY_MODE} ${env.DEPLOY_ENV}: ${env.IMAGE_TAG}"
        }
        unsuccessful {
            echo 'Deployment did not complete. Inspect retained Swarm migration tasks before retrying.'
        }
        cleanup {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}
