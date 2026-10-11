pub(crate) fn mode(enabled: bool, always_on: &str) -> &'static str {
    if !enabled {
        "off"
    } else if always_on == "Y" {
        "always"
    } else {
        "session"
    }
}

pub(crate) fn mode_options(mode: &str) -> Option<(&'static str, &'static str)> {
    match mode {
        "off" => Some(("N", "N")),
        "session" => Some(("Y", "N")),
        "always" => Some(("Y", "Y")),
        _ => None,
    }
}

pub(crate) fn ambient_enabled(enabled: bool, mode: &str, count: usize) -> bool {
    enabled && mode == "always" && count == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persisted_modes_restore_and_preserve_legacy_default() {
        for value in ["off", "session", "always"] {
            let (enabled, always_on) = mode_options(value).unwrap();
            assert_eq!(mode(enabled != "N", always_on), value);
        }
        assert_eq!(mode(true, ""), "session");
        assert_eq!(mode(false, ""), "off");
        assert_eq!(mode(false, "Y"), "off");
        assert!(mode_options("unknown").is_none());
    }

    #[test]
    fn ambient_glow_survives_disconnect_only_in_always_mode() {
        assert!(ambient_enabled(true, "always", 0));
        assert!(!ambient_enabled(false, "always", 0));
        assert!(!ambient_enabled(true, "session", 0));
        assert!(!ambient_enabled(false, "off", 0));
        assert!(!ambient_enabled(true, "always", 1));
    }
}
