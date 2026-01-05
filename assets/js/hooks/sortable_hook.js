import Sortable from "../../vendor/sortable";

export const SortableHook = {
  mounted() {
    const container = this.el;
    
    this.sortable = Sortable.create(container, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "opacity-50",
      chosenClass: "bg-base-300",
      dragClass: "shadow-lg",
      onEnd: (evt) => {
        const items = container.querySelectorAll("[data-index]");
        const newOrder = Array.from(items).map(item => parseInt(item.dataset.index, 10));
        this.pushEvent("reorder_messages", { order: newOrder });
      }
    });
  },

  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }
};

