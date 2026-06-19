import { useEffect, useState } from 'react'
import {
  Badge,
  Box,
  Button,
  Card,
  Checkbox,
  Code,
  Flex,
  Grid,
  Heading,
  RadioGroup,
  Separator,
  Text,
} from '@radix-ui/themes'
import { SkillManagerService } from '../bindings/github.com/rokasklive/go-poc'
import type {
  Assistant,
  Role,
  RuntimeInfo,
  Skill,
} from '../bindings/github.com/rokasklive/go-poc'

// The three backend operations the action buttons can trigger. Each maps 1:1
// to a Go method on SkillManagerService.
type ActionKind = 'Install' | 'Update' | 'Delete'

// techSummary is static copy describing what this POC is built from. It is not
// fetched from the backend — it documents the stack for whoever runs the app.
const techSummary: string[] = [
  'Go backend',
  'Wails v3 desktop shell',
  'React + Vite + TypeScript frontend',
  'Radix UI (Radix Themes)',
  'Node required at build time only',
  'Node NOT required at runtime',
]

function App() {
  const [runtimeInfo, setRuntimeInfo] = useState<RuntimeInfo | null>(null)
  const [assistants, setAssistants] = useState<Assistant[]>([])
  const [roles, setRoles] = useState<Role[]>([])
  const [skills, setSkills] = useState<Skill[]>([])

  const [selectedAssistant, setSelectedAssistant] = useState<string>('')
  const [selectedSkillIDs, setSelectedSkillIDs] = useState<string[]>([])
  const [status, setStatus] = useState<string>('Loading data from the Go backend…')

  // Load all dummy data from the Go backend once, on mount. This is the core
  // proof of the POC: the React frontend calling Go methods through Wails.
  useEffect(() => {
    Promise.all([
      SkillManagerService.GetRuntimeInfo(),
      SkillManagerService.ListAssistants(),
      SkillManagerService.ListRoles(),
      SkillManagerService.ListSkills(),
    ])
      .then(([info, assistantList, roleList, skillList]) => {
        setRuntimeInfo(info)
        setAssistants(assistantList ?? [])
        setRoles(roleList ?? [])
        setSkills(skillList ?? [])
        if (assistantList && assistantList.length > 0) {
          setSelectedAssistant(assistantList[0].id)
        }
        setStatus('Loaded assistants, roles and skills from the Go backend.')
      })
      .catch((err: unknown) => {
        setStatus(`Backend call failed: ${String(err)}`)
      })
  }, [])

  const toggleSkill = (skillID: string) => {
    setSelectedSkillIDs((current) =>
      current.includes(skillID)
        ? current.filter((id) => id !== skillID)
        : [...current, skillID],
    )
  }

  const applyRole = (role: Role) => {
    setSelectedSkillIDs(role.skillIDs ?? [])
    setStatus(`Applied preset "${role.name}" (selection only — no backend call).`)
  }

  const selectAllSkills = () => {
    setSelectedSkillIDs(skills.map((skill) => skill.id))
    setStatus('Selected all skills (selection only — no backend call).')
  }

  // runAction calls the matching Go method once per selected skill and shows
  // every dummy result in the status area.
  const runAction = async (kind: ActionKind) => {
    if (selectedSkillIDs.length === 0) {
      setStatus('Select at least one skill first.')
      return
    }

    const call =
      kind === 'Install'
        ? SkillManagerService.InstallSkill
        : kind === 'Update'
          ? SkillManagerService.UpdateSkill
          : SkillManagerService.DeleteSkill

    setStatus(`Calling ${kind}Skill on the Go backend…`)
    try {
      const messages = await Promise.all(selectedSkillIDs.map((id) => call(id)))
      setStatus(messages.join('\n'))
    } catch (err: unknown) {
      setStatus(`Backend call failed: ${String(err)}`)
    }
  }

  return (
    <Box className="app-shell">
      <Heading size="8" mb="1">
        Skill Manager POC
      </Heading>
      <Text color="gray" size="2">
        A build/distribution feasibility POC. No real skill operations are performed.
      </Text>

      <Grid columns={{ initial: '1', md: '2' }} gap="4" mt="4">
        {/* Technology summary */}
        <Card>
          <Heading size="3" mb="2">
            Technology summary
          </Heading>
          <Flex direction="column" gap="2">
            {techSummary.map((item) => (
              <Text key={item} size="2">
                • {item}
              </Text>
            ))}
          </Flex>
        </Card>

        {/* Runtime / build info panel */}
        <Card>
          <Heading size="3" mb="2">
            Runtime / build info
          </Heading>
          {runtimeInfo ? (
            <Flex direction="column" gap="1">
              <InfoRow label="OS" value={runtimeInfo.os} />
              <InfoRow label="Architecture" value={runtimeInfo.arch} />
              <InfoRow label="App version" value={runtimeInfo.appVersion} />
              <InfoRow label="Go version" value={runtimeInfo.goVersion} />
              <Flex justify="between" align="center">
                <Text size="2" color="gray">
                  Backend status
                </Text>
                <Badge color="green">{runtimeInfo.backendStatus}</Badge>
              </Flex>
            </Flex>
          ) : (
            <Text size="2" color="gray">
              Waiting for backend…
            </Text>
          )}
        </Card>
      </Grid>

      {/* Assistant selector */}
      <Card mt="4">
        <Heading size="3" mb="2">
          Assistant
        </Heading>
        <RadioGroup.Root value={selectedAssistant} onValueChange={setSelectedAssistant}>
          <Flex gap="4" wrap="wrap">
            {assistants.map((assistant) => (
              <RadioGroup.Item key={assistant.id} value={assistant.id}>
                {assistant.name}
              </RadioGroup.Item>
            ))}
          </Flex>
        </RadioGroup.Root>
      </Card>

      {/* Role presets */}
      <Card mt="4">
        <Heading size="3" mb="2">
          Role presets
        </Heading>
        <Flex gap="2" wrap="wrap">
          {roles.map((role) => (
            <Button key={role.id} variant="soft" onClick={() => applyRole(role)}>
              {role.name}
            </Button>
          ))}
          <Button variant="soft" color="gray" onClick={selectAllSkills}>
            Select All
          </Button>
        </Flex>
      </Card>

      {/* Skills list */}
      <Card mt="4">
        <Heading size="3" mb="2">
          Skills
        </Heading>
        <Flex direction="column" gap="2">
          {skills.map((skill) => (
            <Text as="label" size="2" key={skill.id}>
              <Flex gap="2" align="center">
                <Checkbox
                  checked={selectedSkillIDs.includes(skill.id)}
                  onCheckedChange={() => toggleSkill(skill.id)}
                />
                <Box>
                  <Text weight="medium">{skill.name}</Text>{' '}
                  <Text color="gray">— {skill.description}</Text>
                </Box>
              </Flex>
            </Text>
          ))}
        </Flex>

        <Separator size="4" my="3" />

        <Flex gap="2" wrap="wrap">
          <Button onClick={() => runAction('Install')}>Install</Button>
          <Button color="amber" onClick={() => runAction('Update')}>
            Update
          </Button>
          <Button color="red" onClick={() => runAction('Delete')}>
            Delete
          </Button>
        </Flex>
      </Card>

      {/* Status message area */}
      <Card mt="4">
        <Heading size="3" mb="2">
          Last backend result
        </Heading>
        <Code
          variant="ghost"
          size="2"
          style={{ whiteSpace: 'pre-wrap', display: 'block' }}
        >
          {status}
        </Code>
      </Card>
    </Box>
  )
}

// InfoRow renders a single label/value row in the runtime info panel.
function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <Flex justify="between" align="center">
      <Text size="2" color="gray">
        {label}
      </Text>
      <Code variant="ghost">{value}</Code>
    </Flex>
  )
}

export default App
