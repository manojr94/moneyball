import * as RadixTooltip from '@radix-ui/react-tooltip'
import PropTypes from 'prop-types'

export function TooltipProvider({ children }) {
  return <RadixTooltip.Provider delayDuration={300}>{children}</RadixTooltip.Provider>
}

TooltipProvider.propTypes = { children: PropTypes.node.isRequired }

export function Tooltip({ content, children }) {
  return (
    <RadixTooltip.Root>
      <RadixTooltip.Trigger asChild>{children}</RadixTooltip.Trigger>
      <RadixTooltip.Portal>
        <RadixTooltip.Content
          className="z-50 max-w-xs rounded-md bg-slate-900 px-3 py-1.5 text-xs text-white shadow-md animate-in fade-in-0 zoom-in-95"
          sideOffset={4}
        >
          {content}
          <RadixTooltip.Arrow className="fill-slate-900" />
        </RadixTooltip.Content>
      </RadixTooltip.Portal>
    </RadixTooltip.Root>
  )
}

Tooltip.propTypes = {
  content: PropTypes.string.isRequired,
  children: PropTypes.node.isRequired,
}
