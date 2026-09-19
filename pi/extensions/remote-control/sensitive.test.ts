import assert from "node:assert/strict";
import test from "node:test";
import { sensitiveOperation } from "./sensitive.ts";

const bash = (command: string) => sensitiveOperation("bash", { command })?.kind;

test("merges, branch deletions, deployments, and privileged commands are sensitive", () => {
	const cases: [string, string][] = [
		["git merge feature", "merge"],
		["git -C ../repo merge --no-ff feature", "merge"],
		["gh pr merge 12 --squash", "merge"],
		["cd repo && git fetch && git merge origin/main", "merge"],
		["git branch -D rc/old", "branch-deletion"],
		["git branch --delete rc/old", "branch-deletion"],
		["git push origin --delete rc/old", "branch-deletion"],
		["git push origin :rc/old", "branch-deletion"],
		["npm publish", "deployment"],
		["npm run deploy", "deployment"],
		["./scripts/deploy.sh prod", "deployment"],
		["terraform apply -auto-approve", "deployment"],
		["kubectl apply -f k8s/", "deployment"],
		["gh release create v1.2.0", "deployment"],
		["docker push ghcr.io/me/app:latest", "deployment"],
		["sudo pacman -Syu", "privileged"],
		["FOO=1 sudo -E make install", "privileged"],
		["echo ok; doas reboot", "privileged"],
		["(pkexec rm -rf /opt/x)", "privileged"],
		["su -c 'id'", "privileged"],
	];
	for (const [command, kind] of cases) assert.equal(bash(command), kind, command);
});

test("everyday commands are not sensitive", () => {
	for (const command of [
		"git status",
		"git log --grep merge",
		"git merge --abort",
		"git branch -a",
		"git branch rc/new",
		"git push -u origin rc/fix",
		"npm test",
		"grep -r deploy docs/",
		"cat deploy.md",
		"echo sudo",
		"ls -la",
	]) assert.equal(bash(command), undefined, command);
});

test("the merge workflow tool is a merge; other tools are not sensitive", () => {
	assert.equal(sensitiveOperation("merge_this", {})?.kind, "merge");
	assert.equal(sensitiveOperation("edit", { path: "deploy.sh" }), undefined);
	assert.equal(sensitiveOperation("bash", {}), undefined);
});

test("the operation names what would run", () => {
	assert.deepEqual(sensitiveOperation("bash", { command: "gh pr merge 12" }), { kind: "merge", title: "Approve merge?", detail: "gh pr merge 12" });
	assert.equal(sensitiveOperation("merge_this", {})?.detail, "merge_this: commit, open a PR, squash-merge it, and delete the branch");
});
