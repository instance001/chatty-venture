#include "generation_output.h"
#include "llama-grammar.h"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <memory>

void check(bool condition, const char * message) {
    if (!condition) {
        std::cerr << message << std::endl;
        std::exit(1);
    }
}

bool accepts(const std::string & text) {
    std::unique_ptr<llama_grammar, decltype(&llama_grammar_free_impl)> grammar(
        llama_grammar_init_impl(nullptr, chatty::kFreeModeGrammar, "root", false,
                                nullptr, 0, nullptr, 0),
        llama_grammar_free_impl);
    check(grammar != nullptr, "Free Mode grammar failed to initialize");
    for (unsigned char character : text) {
        llama_grammar_accept(grammar.get(), character);
        if (llama_grammar_get_stacks(grammar.get()).empty()) return false;
    }
    const auto & stacks = llama_grammar_get_stacks(grammar.get());
    return std::any_of(stacks.begin(), stacks.end(), [](const auto & stack) { return stack.empty(); });
}

int main() {
    const std::string proposal = R"json({"title":"The Quiet Bell","premise":"The bell is silent.","problem":"A rope is missing.","key_anchor":"a blue knot","supporting_character":"Iris the keeper","stakes":"The tide is coming.","escalation":"The storm grows.","ending_image":"The bell rings.","locations":["Quay","Archive","Tower"],"objectives":["Find the rope","Trace the knot","Restore the bell"],"flavour":"Rain and salt air."})json";
    check(accepts(proposal), "Valid proposal rejected");
    check(!accepts("Title: The Lost City of Eldoria"), "Plain prose accepted");
    check(!accepts(proposal.substr(0, proposal.size() - 2)), "Truncated JSON accepted");
    auto two_locations = proposal;
    two_locations.replace(two_locations.find("[\"Quay\",\"Archive\",\"Tower\"]"),
                          std::string("[\"Quay\",\"Archive\",\"Tower\"]").size(), "[\"Quay\",\"Tower\"]");
    check(!accepts(two_locations), "Two-act proposal accepted");
    auto missing_field = proposal;
    missing_field.erase(1, missing_field.find("\"premise\"") - 1);
    check(!accepts(missing_field), "Missing required field accepted");
    auto escaped = proposal;
    escaped.replace(escaped.find("The Quiet Bell"), 14, R"(The \"Quiet\" Bell)");
    check(accepts(escaped), "Escaped JSON string rejected");
    check(chatty::finish_generation_output(proposal, true) == proposal,
          "Structured response lost its closing quote and brace");
    check(chatty::finish_generation_output("The bell rings. Unfinished", false) == "The bell rings.",
          "Normal narration sentence trimming changed");
    std::cout << "Native generation output tests passed." << std::endl;
}
