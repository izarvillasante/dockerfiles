#!/usr/bin/env bash

# Loosely based on https://www.rocker-project.org/use/singularity/

# This is an interesting image from somebody at dockerhub tags:{R_version}-{Seurat_version}
# IMAGE=${IMAGE:-pansapiens/rocker-seurat:4.1.1-4.0.4}

# Here is a modified version of rocker/rstudio I made in github registry:
 IMAGE=${IMAGE:-ghcr.io/izarvillasante/dockerfiles:main}

# A base rstudio image:
# IMAGE=${IMAGE:-rocker/rstudio:latest}

# you can override the IMAGE in the script with the env command:
#IMAGE=rocker/rstudio:4.1.1 ./rstudio.sh

# Create the folders needed for rstudio to work:

mkdir -p -m 770 run var-lib-rstudio-server
cat > database.conf <<END
provider=sqlite
directory=/var/lib/rstudio-server
END

IMAGE_SLASHED=$(echo $IMAGE | sed 's/:/\//g')
R_LIBS_USER=${HOME}/.rstudio-rocker/${IMAGE_SLASHED} # Main path to store installed packages

RSTUDIO_HOME=${HOME}/.rstudio-rocker/${IMAGE_SLASHED}/session
mkdir -p ${HOME}/.rstudio # will bind here RSTUDIO_HOME so it is allways the same when working on rstudio

RSTUDIO_TMP=${HOME}/.rstudio-rocker/${IMAGE_SLASHED}/tmp
RSITELIB=${HOME}/.rstudio-rocker/${IMAGE_SLASHED}/site-library

mkdir -p -m 770 ${R_LIBS_USER} ${RSTUDIO_HOME} ${RSTUDIO_TMP} ${RSITELIB}
mkdir -p ${RSTUDIO_TMP}/var/run

cat > rsession.sh <<END
#!/bin/sh
export R_LIBS_USER=${HOME}/.rstudio-rocker/${IMAGE_SLASHED}

exec /usr/lib/rstudio-server/bin/rsession "\${@}"
END
chmod +x rsession.sh

# Search for a free port to use (needs python):
PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
# Search for a free port (needs netstat)
if [ $? -ne 0 ]; then
  # Set a default port value
  PORT=8787
  until ! netstat -ln | grep "  LISTEN  " | grep -iEo  ":[0-9]+" | cut -d: -f2 | grep -wqc ${PORT};
  do
      ((PORT++))
      echo "Checking port: ${PORT}"
  done
      echo "Got one !"
fi

#Generate the password:
export SINGULARITYENV_PASSWORD=$(openssl rand -base64 15)

# Use a shared cache location if unspecified
export SINGULARITY_CACHEDIR=${SINGULARITY_CACHEDIR:-"/tmp/.cache/singularity"}

# We detect if we are on the bbgcluster by the hostname.
# Hardcode this to `local` if you don't ever use it.
if [[ $HOSTNAME == bbgn* ]]; then
    HPC_ENV="bbgn"
else
    HPC_ENV="local"
fi

echo "Getting required containers ... this may take a while ..."
echo
# by doing `singularity test` we cache the container image without dumping a local sif file here
# mksquashfs isn't installed everywhere, so we pull on a head node
if [[ $HPC_ENV == "bbgn" ]]; then
    singularity test docker://${IMAGE}
    LOCALPORT=8787
    echo "On you local machine, open an SSH tunnel like:"
    echo "  ssh -N -L ${LOCALPORT}:$(hostname -f):${PORT} -p 22022  ${USER}@bbgcluster"
    echo
    echo "Point your web browser at http://localhost:${LOCALPORT}"
    echo
    echo "Login to RStudio with:"
    echo "  username: ${USER}"
    echo "  password: ${SINGULARITYENV_PASSWORD}"
    echo
    echo "Protip: You can choose your version of R from any of the tags listed here: https://hub.docker.com/r/rocker/rstudio/tags"
    echo "        and set the environment variable IMAGE, eg"
    echo "        IMAGE=rocker/rstudio:4.1.1 $(basename "$0")"
    echo
    echo "Starting RStudio Server (R version from image ${IMAGE})"

else
    export LOCALPORT=$PORT
    echo "Point your web browser at http://localhost:${LOCALPORT}"
    echo
    echo "Login to RStudio with:"
    echo "  username: ${USER}"
    echo "  password: ${SINGULARITYENV_PASSWORD}"
    echo
    echo "Protip: You can choose your version of R from any of the tags listed here: https://hub.docker.com/r/rocker/rstudio/tags"
    echo "        and set the environment variable IMAGE, eg"
    echo "        IMAGE=rocker/rstudio:4.1.1 $(basename "$0")"
    echo
    echo "Starting RStudio Server (R version from image ${IMAGE})"
    singularity pull docker://${IMAGE}
fi

# Set some locales to suppress warnings
LC_CTYPE="C"
LC_TIME="C"
LC_MONETARY="C"
LC_PAPER="C"
LC_MEASUREMENT="C"

if [[ $HPC_ENV == 'bbgn' ]]; then
    export SINGULARITY_BIND="${RSTUDIO_HOME}:${HOME}/.rstudio,${RSTUDIO_TMP}:/tmp,${RSTUDIO_TMP}/var:/var/lib/rstudio-server,${RSTUDIO_TMP}/var/run:/var/run/rstudio-server,/workspace,${R_LIBS_USER},rsession.sh:/etc/rstudio/rsession.sh,database.conf:/etc/rstudio/database.conf,${RSITELIB}:/usr/local/lib/R/site-library"
    export SINGULARITYENV_RSTUDIO_SESSION_TIMEOUT=0
    singularity exec --env R_LIBS_USER=${R_LIBS_USER} \
    docker://${IMAGE} \
                     /usr/lib/rstudio-server/bin/rserver --server-user=${USER} --auth-none=0 --auth-pam-helper-path=pam-helper --auth-timeout-minutes=0 --auth-stay-signed-in-days=30 --rsession-path=/etc/rstudio/rsession.sh  --www-port=${PORT} 
else

    singularity exec --bind ${HOME}:/home/rstudio \
                     --bind ${RSTUDIO_HOME}:${HOME}/.rstudio \
                     --bind ${R_LIBS_USER}:${R_LIBS_USER} \
                     --bind ${RSTUDIO_TMP}:/tmp \
                     --bind=${RSTUDIO_TMP}/var:/var/lib/rstudio-server \
                     --bind=${RSTUDIO_TMP}/var/run:/var/run/rstudio-server \
                     --env R_LIBS_USER=${R_LIBS_USER} \
                     docker://${IMAGE} \
                     rserver --database-config-file database.conf --server-user=${USER} --auth-none=0 --auth-pam-helper-path=pam-helper --www-port=${PORT}
fi

printf 'rserver exited' 1>&2