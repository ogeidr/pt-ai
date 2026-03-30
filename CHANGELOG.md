# Changelog

All notable changes to pentest-ai are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-03-30

### Added
- **6 new agents**: vuln-scanner, web-hunter, credential-tester, attack-planner, bug-bounty, ad-attacker (23 total)
- **3 new Tier 2 agents**: vuln-scanner, web-hunter, and ad-attacker can execute commands with user approval
- **install.sh**: interactive installer with global, project, uninstall, update, and status options
- **Semantic versioning**: VERSION file, CHANGELOG, and git tags for all releases
- **Attack chain correlation**: attack-planner agent builds multi-step exploit paths from findings
- **Bug bounty workflows**: dedicated agent for HackerOne, Bugcrowd, and Intigriti methodology

### Changed
- Agent count: 17 to 23
- Tier 2 agent count: 1 to 4
- Updated README with new agents, install script, and versioning
- Updated INSTALL.md with install.sh instructions

## [1.1.0] - 2026-03-30

### Added
- Tier 2 execution mode for recon-advisor agent
- Scope guard shared prompt block for Tier 2 agents
- TIER2-EXECUTION.md documentation
- FAQ section in README
- Competitor comparison section
- Container guide for running tools in Docker
- SCA use case documentation
- Data privacy guide and LLM data handling section
- Getting started guide for first-time Claude users

### Changed
- recon-advisor upgraded from Tier 1 (advisory) to Tier 2 (execution)
- Expanded disclaimer with Tier 2 execution terms

## [1.0.0] - 2026-03-29

### Added
- 17 specialized AI subagents for penetration testing
- 10 offensive operations agents
- 5 defense and analysis agents
- 2 reporting and learning agents
- MITRE ATT&CK mapping for all agents
- Dual offensive/defensive perspective in every response
- 5 example output files
- Landing page with interactive particle network background
- Documentation: AGENT-GUIDE, CUSTOMIZATION, CONTRIBUTING
- MIT License

### Agents (Initial Release)
- engagement-planner
- recon-advisor
- osint-collector
- exploit-guide
- privesc-advisor
- cloud-security
- api-security
- mobile-pentester
- wireless-pentester
- social-engineer
- detection-engineer
- threat-modeler
- forensics-analyst
- malware-analyst
- stig-analyst
- report-generator
- ctf-solver
