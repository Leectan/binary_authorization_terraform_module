####
# Set up provider

module "provider" {
  source = "../root-infrastructure/"
}

####
# Set up Binary Authorization Policy
####
resource "google_binary_authorization_policy" "policy" {
  admission_whitelist_patterns {
    name_pattern= "gcr.io/google_containers/*"
  }
  default_admission_rule {
    evaluation_mode = "ALWAYS_ALLOW"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

  }
  cluster_admission_rules {
    cluster = "${var.cluster}"
    evaluation_mode = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = ["${google_binary_authorization_attestor.attestor.name}"]
  }

}



resource "google_binary_authorization_attestor" "attestor" {
  name = "${var.attestor}"
  attestation_authority_note {
    note_reference = "${google_container_analysis_note.note.name}"
  }
}

resource "google_container_analysis_note" "note" {
  name = "test-attestor-note"
  attestation_authority {
    hint {
      human_readable_name = "Attestor Note"
    }
  }
}