#!/bin/sh
BUILDDIR=/tmp/CFME-build
DOMAIN=miq-Marketplace

if [ -d ${BUILDDIR} ] ; then
    rm -fR ${BUILDDIR}
fi

cd /var/www/miq/vmdb
bin/rake "rhconsulting:miq_ae_datastore:import[${DOMAIN}, ${BUILDDIR}/Automate]"