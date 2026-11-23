//! The calculator of Search: a query that is a calculation gets its answer above the results.
//! "12 * 3.5", "sqrt 2", "5 km in miles", "0x1f to decimal", "20% of 80". Words alone are never a
//! calculation, so "terminal" still finds the terminal.

use serde::Serialize;

#[derive(Serialize, Debug, PartialEq)]
pub struct Answer {
    /// What was asked, as typed
    pub text: String,
    /// What it comes to
    pub value: String,
}

/// The answer to `text` if it is a calculation
pub fn answer(text: &str) -> Option<Answer> {
    let text = text.trim();
    if text.len() < 2 || !text.chars().any(|c| c.is_ascii_digit()) {
        return None;
    }
    let mut context = fend_core::Context::new();
    let result = fend_core::evaluate(text, &mut context).ok()?;
    let value = result.get_main_result().trim();
    // A number alone is no question, and neither is what comes back unchanged
    if value.is_empty() || value == text || text.parse::<f64>().is_ok() {
        return None;
    }
    Some(Answer {
        text: text.to_string(),
        value: value.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::answer;

    #[test]
    fn calculations_have_an_answer() {
        assert_eq!(answer("2 + 2").unwrap().value, "4");
        assert_eq!(answer("12 * 3.5").unwrap().value, "42");
        assert!(answer("5 km in miles").unwrap().value.contains("miles"));
        assert_eq!(answer("0x1f to decimal").unwrap().value, "31");
    }

    #[test]
    fn words_and_plain_numbers_have_none() {
        assert_eq!(answer("terminal"), None);
        assert_eq!(answer("42"), None);
        assert_eq!(answer("zen 2"), None);
        assert_eq!(answer(""), None);
    }
}
