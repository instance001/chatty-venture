#pragma once

#include <string>

namespace chatty {

// Free Mode setup is the only structured request. Constrain both the JSON
// syntax and its required fields, including exactly three acts. Bounded strings
// and whitespace keep small models from spending the whole budget on one field.
inline constexpr char kFreeModeGrammar[] = R"gbnf(
root ::= "{" ws "\"title\"" ws ":" ws string "," ws "\"premise\"" ws ":" ws string "," ws "\"problem\"" ws ":" ws string "," ws "\"key_anchor\"" ws ":" ws string "," ws "\"supporting_character\"" ws ":" ws string "," ws "\"stakes\"" ws ":" ws string "," ws "\"escalation\"" ws ":" ws string "," ws "\"ending_image\"" ws ":" ws string "," ws "\"locations\"" ws ":" ws triple "," ws "\"objectives\"" ws ":" ws triple "," ws "\"flavour\"" ws ":" ws string "}"
triple ::= "[" ws string "," ws string "," ws string "]" ws
string ::= "\"" char{3,160} "\"" ws
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
ws ::= [ \t\n\r]{0,4}
)gbnf";

inline std::string finish_generation_output(const std::string & text, bool structured_output) {
    // JSON punctuation after the last sentence is part of the response.
    if (structured_output) return text;
    const size_t boundary = text.find_last_of(".!?");
    return boundary == std::string::npos ? text : text.substr(0, boundary + 1);
}

}  // namespace chatty
