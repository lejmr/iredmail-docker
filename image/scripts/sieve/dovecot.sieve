# iRedMail's well-known global "before" sieve rule: file spam into Junk
# instead of the INBOX. Runs before every user's personal script, for
# every mailbox on the server (dovecot.conf: `sieve_script before`).
#
# Mail is filed here rather than discarded so nothing is lost silently
# (ACCEPTANCE.md row 9) - Amavis tags spam with the X-Spam-Flag header and
# still delivers it (see image/Dockerfile's amavis 50-user override:
# final_spam_destiny = D_PASS), and this rule moves anything so tagged into
# Junk. `lda_mailbox_autocreate = yes` (dovecot.conf) creates the Junk
# mailbox the first time it is needed.
require ["fileinto"];

if header :contains "X-Spam-Flag" "YES" {
    fileinto "Junk";
}
