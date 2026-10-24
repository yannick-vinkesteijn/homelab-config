# Pull latest changes from git, then pull and redeploy updated images
update:
    git pull
    docker compose pull
    docker compose up -d --remove-orphans
