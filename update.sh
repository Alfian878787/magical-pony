#!/bin/bash
# I am really sorry for anyone who has to work with this, including myself and
# Kat. - mattl
#
# For troubleshooting:
# sudo tail -f /var/log/letsencrypt/letsencrypt.log

set -o errexit
set -o errtrace
set -o nounset

trap '_es=${?};
    _lo=${LINENO};
    _co=${BASH_COMMAND};
    echo "${0}: line ${_lo}: \"${_co}\" exited with a status of ${_es}";
    exit ${_es}' ERR


repo='https://github.com/creativecommons/creativecommons.org.git'
reponame='cc-all-forks'
workdir='/root'
checkoutdir="${workdir}/${reponame}"
resourcedir="${workdir}/magical-pony"
statusfile='/var/www/html/index.html'
certbotargs='-w /var/www/html -d legal.creativecommons.org'

rm -rf "${checkoutdir}"

mkdir -p "${checkoutdir}"

echo '<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Updating the Magical Pony</title>
    <style>
      div {
        background-color:white;
        margin:1em;
        padding:1em;
      }
      h2 {
        clear:both;
      }
      h3 {
        margin-top:0;
      }
      img {
        float:right;
      }
      td, th {
        padding-top:1em;
        text-align:left;
        vertical-align:top;
      }
      .example-lavender {
        background-color:black;
        color:lavender;
      }
      .example-salmon {
        background-color:black;
        color:salmon;
      }
      .mono {
        font-family:monospace;
      }
      .red {
        color:red;
      }
      .run-success {
        background-color:lavender
      }
      .run-error {
        background-color:salmon
      }
      .smaller {
        font-size:smaller;
      }
    </style>
  </head>
  <body class="run-error">
    <h1>Updating the Magical Pony</h1>' > "${statusfile}"
now_utc=$(date -u '+%A %F %T %:::z %Z')
now_bst=$(date '+%A %F %T %:::z %Z')
echo "    <h2>${now_utc}</h2>" >> "${statusfile}"
sed -e's/^/    /' ${resourcedir}/pony.img.html >> "${statusfile}"
echo "    <p class=\"smaller;\">(${now_bst})</p>" >> "${statusfile}"
echo '    <p>
      <a href="https://github.com/creativecommons/magical-pony">
        https://github.com/creativecommons/magical-pony
      </a>
    </p>
    <p class="smaller">
      On an incomplete or error completion, this page will have a
      <span class="example-salmon">[ SALMON ]</span> background.
    </p>
    <p class="smaller">
      On successful completion, this page will have a
      <span class="example-lavender">[ LAVENDER ]</span> background.
    </p>' >> "${statusfile}"

pushd "${checkoutdir}" > /dev/null
echo

echo "# git clone ${repo}"
# Get a clean version to avoid any merge/reset weirdness
git clone "${repo}" .
echo

echo '    <h2>Branches</h2>' >> "${statusfile}"

for branchname in $(git branch -r | grep -v 'HEAD\|master')
do
    echo "# ${branchname}"
    branchid="${branchname##*/}"
    if [[ -n "${branchid//[-.[:alnum:]]/}" ]]
    then
        {
            echo '    <div>'
            echo '      <hr>'
            echo "      <h3 style=\"color:red;\">${branchid}</h3>"
            echo '      <p class="redsmaller">'
            echo "        (<span class=\"mono\">${branchname}</span>)"
            echo '      </p>'
            echo -n "      <p style=\"color:red;\">The branchid (${branchid})"
            echo ' is not a valid DNS domain name</p>'
            echo -n '      <p style=\"color:red;\"><strong>SKIPPING DEPLOYMENT'
            echo '</strong></p>'
            echo '    </div>'
            echo
        } >> "${statusfile}"
        continue
    fi
    branchpath="/srv/clones/${branchid}"
    webroot="${branchpath}/docroot"
    domain="${branchid}.legal.creativecommons.org"
    certbotargs="${certbotargs:-} -w ${webroot} -d ${domain}"
    echo "${branchpath}"
    git checkout -f -q "${branchname}"
    git show-branch --sha1-name HEAD
    #
    mkdir -p "${branchpath}.NEW"
    git archive "${branchname}" \
        | tar -xC "${branchpath}.NEW"
    [[ -d ${branchpath} ]] && mv ${branchpath} ${branchpath}.OLD
    mv ${branchpath}.NEW ${branchpath}
    [[ -d ${branchpath}.OLD ]] && rm -rf ${branchpath}.OLD
    # Ensure branchpath mtime is up-to-date
    touch ${branchpath}/.gitignore
    # Delete TLS/SSL config so that it is regenerated by certbot
    #rm -f "/etc/apache2/sites-enabled/${branchid}-le-ssl.conf"
    cp "${resourcedir}/default" \
       "/etc/apache2/sites-enabled/${branchid}.conf"
    sed -e"s/MAGICALPONY/${branchid}/g" -i \
         "/etc/apache2/sites-enabled/${branchid}.conf"
    hash=$(git log ${branchname} -1 --format='%H')
    repo_url='https://github.com/creativecommons/creativecommons.org'
    hash_url="${repo_url}/commit/${hash}"
    {
        echo '    <div>'
        echo "      <h3>${branchid}</h3>"
        echo '      <p class="smaller">'
        echo "        (<span class=\"mono\">${branchname}</span>)"
        echo '      </p>'
        echo '      <table>'
        echo '        <tr>'
        echo '          <th>Test Domain:</th>'
        echo "          <td><a href=\"https://${domain}/\">${domain}</a></td>"
        echo '        </tr>'
        echo '        <tr>'
        echo '          <th>Commit:</th>'
        echo '          <td>'
        echo "            <a class=\"mono\" href=\"${hash_url}\">${hash}</a>"
        echo '            <br>'
    } >> "${statusfile}"
    git log ${branchname} -1 --format='          %s' \
        >> "${statusfile}"
    {
        echo '          </td>'
        echo '        </tr>'
        echo '      </table>'
        echo '    </div>'
        echo
    }  >> "${statusfile}"
    echo
done

popd > /dev/null

echo
echo '# apache2 restart'
/usr/sbin/service apache2 restart
sleep 1

echo
echo '# cerbotargs:'
echo "${certbotargs}"
echo
echo '# run cerbot'
echo
# Get any new certificates, incorporate old one, refresh expiring, install any
# new http->https redirects, and do so automatically.
if /usr/bin/certbot \
    --agree-tos -m webmaster@creativecommons.org \
    --non-interactive \
    --cert-name legal.creativecommons.org \
    --keep-until-expiring \
    --expand \
    --renew-with-new-domains \
    --authenticator webroot \
    --installer apache \
    ${certbotargs}
then
    echo '    <h2>And we are done!</h2>' >> "${statusfile}"
else
    {
        echo '    <h2>certbot ERROR</h2>'
        echo '    <p>See:'
        echo '        <pre>/var/log/letsencrypt/letsencrypt.log</pre>'
        echo '        <pre>/var/log/magical-pony</pre>'
        echo '        <pre>/var/log/mail/mail</pre>'
        echo '    </p>'
    } >> "${statusfile}"
fi
echo

now_utc=$(date -u '+%A %F %T %:::z %Z')
now_bst=$(date '+%A %F %T %:::z %Z')
echo "    <h3>${now_utc}</h3>" >> "${statusfile}"
echo "    <p class=\"smaller;\">(${now_bst})</p>" >> "${statusfile}"
echo '  </body>' >> "${statusfile}"
echo '</html>' >> "${statusfile}"

# Touch primary apache files to ensure they are preserved
touch /etc/apache2/sites-enabled/legal.creativecommons.org.conf
touch /etc/apache2/sites-enabled/legal.creativecommons.org-le-ssl.conf

echo 'Directories older than 24 hours are deleted by magical-pony update.sh' \
    > /srv/clones/README
echo '# Clean-up: /srv/clones'
find /srv/clones/* -maxdepth 0 -type d -mtime +1
find /srv/clones/* -maxdepth 0 -type d -mtime +1 -exec rm -rf {} +
echo

echo 'Files older than 24 hours are deleted by magical-pony update.sh' \
    > /etc/apache2/sites-enabled/README
echo '# Clean-up: /etc/apache2/sites-enabled/'
find /etc/apache2/sites-enabled -mtime +1
find /etc/apache2/sites-enabled -mtime +1 -delete
echo

echo '# apache2 restart'
/usr/sbin/service apache2 restart

sed -e's/"run-error"/"run-success"/' -i "${statusfile}"
