#!/usr/bin/env bash

# Set project ID
gcloud config set project ${PROJECT_ID}


ATTESTOR="manually-verified" # No spaces allowed
ATTESTOR_NAME="Manual Attestor"
ATTESTOR_EMAIL="$(gcloud config get-value core/account)" # This uses your current user/email

#Container Analysis Note ID/description of your attestation authority:
NOTE_ID="Human-Attestor-Note" # No spaces
NOTE_DESC="Human Attestation Note Demo"

#Names for files to create payloads/requests:
NOTE_PAYLOAD_PATH="note_payload.json"
IAM_REQUEST_JSON="iam_request.json"

#Create the ATTESTATION note payload

cat > ${NOTE_PAYLOAD_PATH} << EOF
{
  "name": "projects/${PROJECT_ID}/notes/${NOTE_ID}",
  "attestation_authority": {
    "hint": {
      "human_readable_name": "${NOTE_DESC}"
    }
  }
}
EOF

#Submit the ATTESTATION note to the Container Analysis API:

curl -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)"  \
    --data-binary @${NOTE_PAYLOAD_PATH}  \
    "https://containeranalysis.googleapis.com/v1beta1/projects/${PROJECT_ID}/notes/?noteId=${NOTE_ID}"

#create a new PGP key and export the public PGP key
PGP_PUB_KEY="generated-key.pgp"

#Create the PGP key:
sudo apt-get install rng-tools
sudo rngd -r /dev/urandom
gpg --quick-generate-key --yes ${ATTESTOR_EMAIL}

#Extract the public PGP key:

gpg --armor --export "${ATTESTOR_EMAIL}" > ${PGP_PUB_KEY}

#Create the Attestor in the Binary Authorization API:
gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors create "${ATTESTOR}" \
    --attestation-authority-note="${NOTE_ID}" \
    --attestation-authority-note-project="${PROJECT_ID}"

#Add the PGP Key to the Attestor:
gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors public-keys add \
    --attestor="${ATTESTOR}" \
    --public-key-file="${PGP_PUB_KEY}"

#List the newly created Attestor:
gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors list

#Signing" a Container Image
#The preceeding steps only need to be performed once. From this point on, this step is the only step that needs repeating for every new container image.
#Set a few shell variables:

GENERATED_PAYLOAD="generated_payload.json"
GENERATED_SIGNATURE="generated_signature.pgp"

#Get the PGP fingerprint:
PGP_FINGERPRINT="$(gpg --list-keys ${ATTESTOR_EMAIL} | head -2 | tail -1 | awk '{print $1}')"

#Obtain the SHA256 Digest of the container image:
IMAGE_PATH="gcr.io/${PROJECT_ID}/nginx"
IMAGE_DIGEST="$(gcloud container images list-tags --format='get(digest)' $IMAGE_PATH | head -1)"

#Create a JSON-formatted signature payload:
gcloud beta container binauthz create-signature-payload \
    --artifact-url="${IMAGE_PATH}@${IMAGE_DIGEST}" > ${GENERATED_PAYLOAD}

#View the generated signature payload:
cat "${GENERATED_PAYLOAD}"

#"Sign" the payload with the PGP key:
gpg --local-user "${ATTESTOR_EMAIL}" \
    --armor \
    --output ${GENERATED_SIGNATURE} \
    --sign ${GENERATED_PAYLOAD}

#View the generated signature (PGP message):
cat "${GENERATED_SIGNATURE}"

#Create the attestation:
gcloud beta container binauthz attestations create \
    --artifact-url="${IMAGE_PATH}@${IMAGE_DIGEST}" \
    --attestor="projects/${PROJECT_ID}/attestors/${ATTESTOR}" \
    --signature-file=${GENERATED_SIGNATURE} \
    --pgp-key-fingerprint="${PGP_FINGERPRINT}"

#View the newly created attestation:
gcloud beta container binauthz attestations list \
    --attestor="projects/${PROJECT_ID}/attestors/${ATTESTOR}"

#Below output can be used for attestation authority rule
echo "projects/${PROJECT_ID}/attestors/${ATTESTOR}" # Copy this output to your copy/paste buffer

