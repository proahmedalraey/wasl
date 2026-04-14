<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import AgentBotsAPI from 'dashboard/api/agentBots';
import { VueFlow, addEdge } from '@vue-flow/core';
import dagre from 'dagre';
import '@vue-flow/core/dist/style.css';
import '@vue-flow/core/dist/theme-default.css';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const dialogRef = ref(null);
const loading = ref(false);
const bot = ref(null);
const flowName = ref('');
const flowDescription = ref('');
const validationErrors = ref([]);
const visualNodes = ref([]);
const visualEdges = ref([]);
const flowInstance = ref(null);
const selectedNodeId = ref(null);
const definitionMeta = ref({ allow_loops: false });
const definitionTriggers = ref([]);
const definitionVariablesSchema = ref({});

const NODE_WIDTH = 220;
const NODE_HEIGHT = 92;
const NODE_TYPES = [
  { type: 'start' },
  { type: 'send_message' },
  { type: 'ask_input' },
  { type: 'end' },
];

const canSubmit = computed(() => {
  if (!bot.value) return false;
  return visualNodes.value.length > 0;
});

const defaultDefinition = () => ({
  meta: { allow_loops: false },
  triggers: [],
  variables_schema: {},
  nodes: [
    { id: 'start', type: 'start', data: {}, position: { x: 80, y: 80 } },
    {
      id: 'welcome',
      type: 'send_message',
      data: { text: replaceInstallationName('Welcome to Chatwoot.') },
      position: { x: 320, y: 80 },
    },
    { id: 'end', type: 'end', data: {}, position: { x: 540, y: 80 } },
  ],
  edges: [
    { id: 'e1', source: 'start', target: 'welcome' },
    { id: 'e2', source: 'welcome', target: 'end' },
  ],
});

const nodeTypeLabel = type => {
  if (type === 'start') return t('AGENT_BOTS.BUILDER.NODE_TYPES.START');
  if (type === 'send_message') {
    return t('AGENT_BOTS.BUILDER.NODE_TYPES.SEND_MESSAGE');
  }
  if (type === 'ask_input') return t('AGENT_BOTS.BUILDER.NODE_TYPES.ASK_INPUT');
  return t('AGENT_BOTS.BUILDER.NODE_TYPES.END');
};

const flowNodeLabel = (type, data = {}) => {
  if (type === 'send_message') {
    return data.text || t('AGENT_BOTS.BUILDER.NODE_TYPES.SEND_MESSAGE');
  }
  if (type === 'ask_input') {
    return data.prompt || t('AGENT_BOTS.BUILDER.NODE_TYPES.ASK_INPUT');
  }
  return nodeTypeLabel(type);
};

const createVisualNode = ({
  id,
  type,
  data = {},
  position = { x: 0, y: 0 },
}) => ({
  id,
  type: 'default',
  position,
  data: {
    kind: type,
    ...data,
    label: flowNodeLabel(type, data),
  },
  class: 'rounded-lg border border-n-slate-3 bg-n-background p-2 shadow-sm',
});

const deserializeDefinition = definition => {
  const normalizedDefinition = definition || defaultDefinition();
  definitionMeta.value = normalizedDefinition.meta || { allow_loops: false };
  definitionTriggers.value = normalizedDefinition.triggers || [];
  definitionVariablesSchema.value = normalizedDefinition.variables_schema || {};

  const normalizedNodes = Array.isArray(normalizedDefinition.nodes)
    ? normalizedDefinition.nodes
    : [];
  const normalizedEdges = Array.isArray(normalizedDefinition.edges)
    ? normalizedDefinition.edges
    : [];

  visualNodes.value = normalizedNodes.map((node, index) =>
    createVisualNode({
      id: String(node.id),
      type: node.type || 'send_message',
      data: node.data || {},
      position: node.position || { x: 120 + index * 250, y: 120 },
    })
  );

  visualEdges.value = normalizedEdges
    .filter(edge => edge.source && edge.target)
    .map((edge, index) => ({
      id: edge.id || `edge_${index}_${edge.source}_${edge.target}`,
      source: String(edge.source),
      target: String(edge.target),
      data: edge.condition ? { condition: edge.condition } : {},
    }));
};

const serializeDefinition = () => ({
  meta: definitionMeta.value || { allow_loops: false },
  triggers: Array.isArray(definitionTriggers.value)
    ? definitionTriggers.value
    : [],
  variables_schema:
    definitionVariablesSchema.value &&
    typeof definitionVariablesSchema.value === 'object'
      ? definitionVariablesSchema.value
      : {},
  nodes: visualNodes.value.map(node => ({
    id: node.id,
    type: node.data?.kind || 'send_message',
    data: (() => {
      if (node.data?.kind === 'send_message') {
        return { text: node.data?.text || '' };
      }
      if (node.data?.kind === 'ask_input') {
        return {
          prompt: node.data?.prompt || '',
          variable_key: node.data?.variable_key || '',
        };
      }
      return {};
    })(),
    position: {
      x: Math.round(node.position?.x || 0),
      y: Math.round(node.position?.y || 0),
    },
  })),
  edges: visualEdges.value.map(edge => ({
    id: edge.id,
    source: edge.source,
    target: edge.target,
    ...(edge.data?.condition ? { condition: edge.data.condition } : {}),
  })),
});

const extractBackendErrors = error => {
  const errors = error?.response?.data?.errors;
  return Array.isArray(errors) ? errors : [];
};

const loadFlow = async botId => {
  loading.value = true;
  try {
    const { data } = await AgentBotsAPI.getFlow(botId);
    flowName.value = data.name || '';
    flowDescription.value = data.description || '';
    deserializeDefinition(data.draft_definition || defaultDefinition());
    selectedNodeId.value = null;
    validationErrors.value = [];
    await nextTick();
    flowInstance.value?.fitView({ padding: 0.2, duration: 300 });
  } catch (error) {
    useAlert(t('AGENT_BOTS.BUILDER.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const open = selectedBot => {
  bot.value = selectedBot;
  dialogRef.value.open();
  loadFlow(selectedBot.id);
};

const saveDraft = async () => {
  loading.value = true;
  try {
    const definition = serializeDefinition();
    await AgentBotsAPI.updateFlowDraft(bot.value.id, {
      name: flowName.value,
      description: flowDescription.value,
      definition,
    });
    validationErrors.value = [];
    useAlert(t('AGENT_BOTS.BUILDER.SAVE_SUCCESS'));
  } catch (error) {
    validationErrors.value = extractBackendErrors(error);
    const firstError = validationErrors.value[0];
    useAlert(firstError || t('AGENT_BOTS.BUILDER.SAVE_ERROR'));
    if (firstError) return;
    useAlert(t('AGENT_BOTS.BUILDER.SAVE_ERROR'));
  } finally {
    loading.value = false;
  }
};

const validateDraft = async () => {
  loading.value = true;
  try {
    const definition = serializeDefinition();
    const { data } = await AgentBotsAPI.validateFlow(bot.value.id, {
      definition,
    });
    validationErrors.value = data.errors || [];
    if (data.valid) {
      useAlert(t('AGENT_BOTS.BUILDER.VALIDATE_SUCCESS'));
    } else {
      useAlert(
        validationErrors.value[0] || t('AGENT_BOTS.BUILDER.VALIDATE_ERROR')
      );
    }
  } catch (error) {
    validationErrors.value = extractBackendErrors(error);
    useAlert(
      validationErrors.value[0] || t('AGENT_BOTS.BUILDER.VALIDATE_ERROR')
    );
  } finally {
    loading.value = false;
  }
};

const publishDraft = async () => {
  loading.value = true;
  try {
    const definition = serializeDefinition();
    const { data } = await AgentBotsAPI.publishFlow(bot.value.id, {
      definition,
    });
    validationErrors.value = [];
    if (data?.published_version) {
      useAlert(
        t('AGENT_BOTS.BUILDER.PUBLISH_SUCCESS', {
          version: data.published_version.version,
        })
      );
    } else {
      useAlert(t('AGENT_BOTS.BUILDER.PUBLISH_SUCCESS_GENERIC'));
    }
  } catch (error) {
    validationErrors.value = extractBackendErrors(error);
    useAlert(
      validationErrors.value[0] || t('AGENT_BOTS.BUILDER.PUBLISH_ERROR')
    );
  } finally {
    loading.value = false;
  }
};

const onFlowInit = instance => {
  flowInstance.value = instance;
};

const onConnect = connection => {
  visualEdges.value = addEdge(connection, visualEdges.value);
};

const onNodeSelect = ({ node }) => {
  selectedNodeId.value = node?.id || null;
};

const selectedNode = computed(
  () => visualNodes.value.find(node => node.id === selectedNodeId.value) || null
);

const updateSelectedNodeData = updates => {
  if (!selectedNode.value) return;

  visualNodes.value = visualNodes.value.map(node => {
    if (node.id !== selectedNode.value.id) return node;
    const data = { ...node.data, ...updates };
    return {
      ...node,
      data: {
        ...data,
        label: flowNodeLabel(data.kind, data),
      },
    };
  });
};

const startNodeDrag = (event, type) => {
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('application/vueflow', type);
};

const addNodeToCanvas = (type, position) => {
  const id = `${type}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  let baseData = {};
  if (type === 'send_message') {
    baseData = { text: t('AGENT_BOTS.BUILDER.DEFAULT_SEND_MESSAGE_TEXT') };
  } else if (type === 'ask_input') {
    baseData = {
      prompt: t('AGENT_BOTS.BUILDER.DEFAULT_ASK_INPUT_PROMPT'),
      variable_key: 'response',
    };
  }

  visualNodes.value = [
    ...visualNodes.value,
    createVisualNode({
      id,
      type,
      data: baseData,
      position,
    }),
  ];
};

const onCanvasDrop = event => {
  event.preventDefault();
  if (!flowInstance.value) return;
  const type = event.dataTransfer.getData('application/vueflow');
  if (!type) return;

  const bounds = event.currentTarget.getBoundingClientRect();
  const position = flowInstance.value.screenToFlowCoordinate({
    x: event.clientX - bounds.left,
    y: event.clientY - bounds.top,
  });
  addNodeToCanvas(type, position);
};

const onCanvasDragOver = event => {
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
};

const autoLayout = async () => {
  if (!visualNodes.value.length) return;

  const graph = new dagre.graphlib.Graph();
  graph.setGraph({ rankdir: 'LR', ranksep: 80, nodesep: 40 });
  graph.setDefaultEdgeLabel(() => ({}));

  visualNodes.value.forEach(node => {
    graph.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT });
  });

  visualEdges.value.forEach(edge => {
    graph.setEdge(edge.source, edge.target);
  });

  dagre.layout(graph);

  visualNodes.value = visualNodes.value.map(node => {
    const position = graph.node(node.id);
    if (!position) return node;
    return {
      ...node,
      position: {
        x: Math.round(position.x - NODE_WIDTH / 2),
        y: Math.round(position.y - NODE_HEIGHT / 2),
      },
    };
  });

  await nextTick();
  flowInstance.value?.fitView({ padding: 0.2, duration: 250 });
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('AGENT_BOTS.BUILDER.TITLE', { name: bot?.name || '' })"
    :show-confirm-button="false"
    :show-cancel-button="false"
  >
    <div class="flex flex-col gap-4 min-h-[42rem]">
      <Input
        v-model="flowName"
        :label="t('AGENT_BOTS.BUILDER.FLOW_NAME')"
        :placeholder="t('AGENT_BOTS.BUILDER.FLOW_NAME_PLACEHOLDER')"
      />
      <TextArea
        v-model="flowDescription"
        :label="t('AGENT_BOTS.BUILDER.FLOW_DESCRIPTION')"
        :placeholder="t('AGENT_BOTS.BUILDER.FLOW_DESCRIPTION_PLACEHOLDER')"
      />

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-[280px_minmax(0,1fr)]">
        <div class="rounded-lg border border-n-slate-3 bg-n-background p-3">
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('AGENT_BOTS.BUILDER.TOOLBAR_TITLE') }}
          </p>
          <p class="mt-1 text-xs text-n-slate-10">
            {{ t('AGENT_BOTS.BUILDER.TOOLBAR_HELP') }}
          </p>

          <div class="mt-3 flex flex-col gap-2">
            <button
              v-for="item in NODE_TYPES"
              :key="item.type"
              type="button"
              draggable="true"
              class="rounded-md border border-n-slate-3 bg-white px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-1"
              @dragstart="startNodeDrag($event, item.type)"
            >
              {{ nodeTypeLabel(item.type) }}
            </button>
          </div>

          <Button
            slate
            faded
            class="mt-4 w-full"
            :label="t('AGENT_BOTS.BUILDER.AUTO_LAYOUT')"
            :disabled="visualNodes.length === 0"
            @click="autoLayout"
          />

          <div
            v-if="selectedNode"
            class="mt-4 rounded-md border border-n-slate-3 bg-white p-3"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('AGENT_BOTS.BUILDER.SELECTED_NODE') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{ nodeTypeLabel(selectedNode.data.kind) }}
            </p>

            <Input
              v-if="selectedNode.data.kind === 'send_message'"
              class="mt-3"
              :label="t('AGENT_BOTS.BUILDER.MESSAGE_TEXT')"
              :model-value="selectedNode.data.text || ''"
              @update:model-value="
                value => updateSelectedNodeData({ text: value })
              "
            />

            <Input
              v-if="selectedNode.data.kind === 'ask_input'"
              class="mt-3"
              :label="t('AGENT_BOTS.BUILDER.PROMPT_TEXT')"
              :model-value="selectedNode.data.prompt || ''"
              @update:model-value="
                value => updateSelectedNodeData({ prompt: value })
              "
            />
            <Input
              v-if="selectedNode.data.kind === 'ask_input'"
              class="mt-3"
              :label="t('AGENT_BOTS.BUILDER.VARIABLE_KEY')"
              :model-value="selectedNode.data.variable_key || ''"
              @update:model-value="
                value => updateSelectedNodeData({ variable_key: value })
              "
            />
          </div>
        </div>

        <div
          class="h-[32rem] overflow-hidden rounded-lg border border-n-slate-3 bg-white"
          @drop="onCanvasDrop"
          @dragover="onCanvasDragOver"
        >
          <VueFlow
            v-model:nodes="visualNodes"
            v-model:edges="visualEdges"
            :default-zoom="1"
            :min-zoom="0.25"
            :max-zoom="1.75"
            fit-view-on-init
            class="h-full w-full bg-n-alpha-1"
            @init="onFlowInit"
            @connect="onConnect"
            @node-click="onNodeSelect"
          />
        </div>
      </div>

      <div v-if="validationErrors.length" class="rounded-md bg-n-ruby-2 p-3">
        <p class="text-sm font-medium text-n-ruby-11">
          {{ t('AGENT_BOTS.BUILDER.VALIDATION_ERRORS') }}
        </p>
        <ul class="mt-2 list-disc ltr:pl-4 rtl:pr-4 text-sm text-n-ruby-11">
          <li v-for="error in validationErrors" :key="error">
            {{ error }}
          </li>
        </ul>
      </div>

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          :label="t('AGENT_BOTS.BUILDER.VALIDATE')"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="validateDraft"
        />
        <Button
          slate
          :label="t('AGENT_BOTS.BUILDER.SAVE_DRAFT')"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="saveDraft"
        />
        <Button
          :label="t('AGENT_BOTS.BUILDER.PUBLISH')"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="publishDraft"
        />
      </div>
    </div>
  </Dialog>
</template>
